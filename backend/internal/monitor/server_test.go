package monitor

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestBuildMinioQueryUsesObjectStorageInstance(t *testing.T) {
	server := &Server{ObjectStorageHost: "object-storage.objectorstorage-system.svc.cluster.local:80"}
	request := &promRequest{
		Type:   "minio",
		Query:  "minio_bucket_traffic_sent_bytes",
		Bucket: "user-bucket",
	}

	query, err := server.buildQuery(request, false)
	if err != nil {
		t.Fatalf("buildQuery() error = %v", err)
	}

	expected := `sum(minio_bucket_traffic_sent_bytes{bucket="user-bucket", instance="object-storage.objectorstorage-system.svc.cluster.local:80"}) by (bucket, instance, job, namespace)`
	if query != expected {
		t.Fatalf("buildQuery() = %q, want %q", query, expected)
	}
}

func TestBuildRawQueryScopesNamespace(t *testing.T) {
	server := &Server{}
	request := &promRequest{
		Namespace: "ns-user",
		Query:     `sum(rate(http_requests_total{}[5m])) by (pod) or kube_pod_info$`,
	}

	query, err := server.buildQuery(request, true)
	if err != nil {
		t.Fatalf("buildQuery() error = %v", err)
	}

	expected := `sum(rate(http_requests_total{namespace=~"ns-user",}[5m])) by (pod) or kube_pod_infonamespace=~"ns-user"`
	if query != expected {
		t.Fatalf("buildQuery() = %q, want %q", query, expected)
	}
}

func TestServerDoesNotNeedLeaderElection(t *testing.T) {
	server := &Server{}

	if server.NeedLeaderElection() {
		t.Fatal("monitor server should run on every controller pod")
	}
}

func TestParseRequest(t *testing.T) {
	form := url.Values{}
	form.Set("query", "minio_bucket_usage_total_bytes")
	form.Set("namespace", "ns-user")
	form.Set("type", "minio")
	form.Set("app", "bucket-a")
	form.Set("start", "100")
	form.Set("end", "200")
	form.Set("step", "60")

	req := httptest.NewRequest(http.MethodGet, "/q?"+form.Encode(), nil)
	req.Header.Set("Authorization", url.PathEscape("apiVersion: v1\nclusters: []"))

	parsed, err := parseRequest(req)
	if err != nil {
		t.Fatalf("parseRequest() error = %v", err)
	}

	if parsed.Password != "apiVersion: v1\nclusters: []" {
		t.Fatalf("Password = %q", parsed.Password)
	}
	if parsed.Namespace != "ns-user" || parsed.Query != "minio_bucket_usage_total_bytes" || parsed.Type != "minio" || parsed.Bucket != "bucket-a" {
		t.Fatalf("unexpected parsed request: %#v", parsed)
	}
	if parsed.Range.Start != "100" || parsed.Range.End != "200" || parsed.Range.Step != "60" {
		t.Fatalf("unexpected range: %#v", parsed.Range)
	}
}

func TestQueryPrometheusChoosesRangeEndpoint(t *testing.T) {
	var receivedPath string
	var receivedQuery string
	prometheus := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, req *http.Request) {
		receivedPath = req.URL.Path
		if err := req.ParseForm(); err != nil {
			t.Fatalf("ParseForm() error = %v", err)
		}
		receivedQuery = req.Form.Get("query")
		_ = json.NewEncoder(rw).Encode(map[string]any{
			"status": "success",
			"data": map[string]any{
				"resultType": "matrix",
				"result":     []any{},
			},
		})
	}))
	defer prometheus.Close()

	server := &Server{
		PrometheusURL: prometheus.URL,
		Client:        prometheus.Client(),
	}
	request := &promRequest{
		Range: promRange{
			Start: "100",
			End:   "200",
			Step:  "60",
		},
	}

	body, err := server.queryPrometheus(context.Background(), request, "up")
	if err != nil {
		t.Fatalf("queryPrometheus() error = %v", err)
	}
	if !json.Valid(body) {
		t.Fatalf("queryPrometheus() returned invalid json: %s", string(body))
	}
	if receivedPath != "/api/v1/query_range" {
		t.Fatalf("path = %q, want /api/v1/query_range", receivedPath)
	}
	if receivedQuery != "up" {
		t.Fatalf("query = %q, want up", receivedQuery)
	}
}
