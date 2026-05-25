package monitor

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/go-logr/logr"
	authorizationapi "k8s.io/api/authorization/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	defaultPrometheusURL = "http://vmselect-victoria-metrics-k8s-stack.vm.svc:8481/select/0/prometheus/"
	defaultMinioInstance = "object-storage:80"
)

var (
	errNoPrometheusURL = errors.New("unable to get the prometheus host")
	errEmptyKubeconfig = errors.New("empty kubeconfig")
	errMissingParam    = errors.New("at least provide both namespace and query")
	errNoNamespace     = errors.New("namespace not found")
	errNoSealosHost    = errors.New("unable to get the sealos host")
	errNoAuth          = errors.New("no permission for this namespace")
)

var minioQueries = map[string]string{
	"minio_bucket_usage_object_total":     `minio_bucket_usage_object_total{bucket="@", instance="#"}`,
	"minio_bucket_usage_total_bytes":      `minio_bucket_usage_total_bytes{bucket="@", instance="#"}`,
	"minio_bucket_traffic_received_bytes": `sum(minio_bucket_traffic_received_bytes{bucket="@", instance="#"}) by (bucket, instance, job, namespace)`,
	"minio_bucket_traffic_sent_bytes":     `sum(minio_bucket_traffic_sent_bytes{bucket="@", instance="#"}) by (bucket, instance, job, namespace)`,
}

type Server struct {
	Addr              string
	PrometheusURL     string
	ObjectStorageHost string
	Log               logr.Logger
	Client            *http.Client
}

type promRequest struct {
	Password  string
	Namespace string
	Type      string
	Query     string
	Bucket    string
	Range     promRange
}

type promRange struct {
	Start string
	End   string
	Step  string
	Time  string
}

func New(addr string, log logr.Logger) *Server {
	if addr == "" {
		addr = ":9090"
	}

	prometheusURL := firstNonEmpty(os.Getenv("PROMETHEUS_URL"), os.Getenv("PROMETHEUS_SERVICE_HOST"), defaultPrometheusURL)
	objectStorageHost := firstNonEmpty(os.Getenv("OBJECT_STORAGE_INSTANCE"), os.Getenv("OSInternalEndpoint"), defaultMinioInstance)

	return &Server{
		Addr:              addr,
		PrometheusURL:     strings.TrimRight(prometheusURL, "/"),
		ObjectStorageHost: objectStorageHost,
		Log:               log,
		Client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (s *Server) Start(ctx context.Context) error {
	if s.Addr == "0" {
		s.Log.Info("minio monitor disabled")
		return nil
	}

	httpServer := &http.Server{
		Addr:              s.Addr,
		Handler:           s,
		ReadHeaderTimeout: 10 * time.Second,
	}
	errCh := make(chan error, 1)

	go func() {
		s.Log.Info("starting minio monitor", "addr", s.Addr)
		err := httpServer.ListenAndServe()
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
			return
		}
		close(errCh)
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(shutdownCtx); err != nil {
			return err
		}
		<-errCh
		return nil
	case err := <-errCh:
		return err
	}
}

func (s *Server) NeedLeaderElection() bool {
	return false
}

func (s *Server) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	switch req.URL.Path {
	case "/query":
		s.handleQuery(rw, req, true)
	case "/q":
		s.handleQuery(rw, req, false)
	default:
		http.Error(rw, "Not found", http.StatusNotFound)
	}
}

func (s *Server) handleQuery(rw http.ResponseWriter, req *http.Request, rawQuery bool) {
	pr, err := parseRequest(req)
	if err != nil {
		http.Error(rw, fmt.Sprintf("Bad request (%s)", err), http.StatusBadRequest)
		s.Log.Error(err, "bad monitor request")
		return
	}

	if err := authenticate(pr.Namespace, pr.Password); err != nil {
		http.Error(rw, fmt.Sprintf("Authentication failed (%s)", err), http.StatusInternalServerError)
		s.Log.Error(err, "monitor authentication failed", "namespace", pr.Namespace)
		return
	}

	query, err := s.buildQuery(pr, rawQuery)
	if err != nil {
		http.Error(rw, fmt.Sprintf("Query failed (%s)", err), http.StatusBadRequest)
		s.Log.Error(err, "failed to build monitor query", "namespace", pr.Namespace, "query", pr.Query)
		return
	}

	body, err := s.queryPrometheus(req.Context(), pr, query)
	if err != nil {
		http.Error(rw, fmt.Sprintf("Query failed (%s)", err), http.StatusInternalServerError)
		s.Log.Error(err, "failed to query prometheus", "namespace", pr.Namespace, "query", pr.Query)
		return
	}

	rw.Header().Set("Content-Type", "application/json")
	_, _ = rw.Write(body)
}

func parseRequest(req *http.Request) (*promRequest, error) {
	pr := &promRequest{}

	password, err := url.PathUnescape(req.Header.Get("Authorization"))
	if err != nil {
		return nil, err
	}
	if password == "" {
		return nil, errEmptyKubeconfig
	}
	pr.Password = password

	if err := req.ParseForm(); err != nil {
		return nil, err
	}

	pr.Query = req.Form.Get("query")
	pr.Range.Step = req.Form.Get("step")
	pr.Range.Start = req.Form.Get("start")
	pr.Range.End = req.Form.Get("end")
	pr.Range.Time = req.Form.Get("time")
	pr.Namespace = req.Form.Get("namespace")
	pr.Type = req.Form.Get("type")
	pr.Bucket = req.Form.Get("app")

	if pr.Namespace == "" || pr.Query == "" {
		return nil, errMissingParam
	}

	return pr, nil
}

func (s *Server) buildQuery(pr *promRequest, rawQuery bool) (string, error) {
	if rawQuery {
		result := strings.ReplaceAll(pr.Query, "$", `namespace=~"`+pr.Namespace+`"`)
		return strings.ReplaceAll(result, "{", `{namespace=~"`+pr.Namespace+`",`), nil
	}

	if pr.Type != "minio" {
		return "", fmt.Errorf("unsupported monitor type %q", pr.Type)
	}

	result, ok := minioQueries[pr.Query]
	if !ok {
		return "", fmt.Errorf("unsupported minio query %q", pr.Query)
	}

	result = strings.ReplaceAll(result, "#", s.ObjectStorageHost)
	result = strings.ReplaceAll(result, "@", pr.Bucket)
	return result, nil
}

func (s *Server) queryPrometheus(ctx context.Context, pr *promRequest, query string) ([]byte, error) {
	if s.PrometheusURL == "" {
		return nil, errNoPrometheusURL
	}

	formData := url.Values{}
	formData.Set("query", query)
	if pr.Range.Start != "" {
		formData.Set("start", pr.Range.Start)
		formData.Set("end", pr.Range.End)
		formData.Set("step", pr.Range.Step)
	} else if pr.Range.Time != "" {
		formData.Set("time", pr.Range.Time)
	}

	path := "/api/v1/query"
	if formData.Get("start") != "" {
		path = "/api/v1/query_range"
	}

	endpoint := s.PrometheusURL + path
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewBufferString(formData.Encode()))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := s.Client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("prometheus server: %s", resp.Status)
	}
	if !json.Valid(body) {
		return nil, fmt.Errorf("prometheus returned invalid json")
	}
	return body, nil
}

func authenticate(namespace, kubeconfig string) error {
	if namespace == "" {
		return errNoNamespace
	}

	config, err := clientcmd.RESTConfigFromKubeConfig([]byte(kubeconfig))
	if err != nil {
		return fmt.Errorf("kubeconfig failed: %w", err)
	}
	if !isWhitelistedKubernetesHost(config.Host) {
		if k8sHost := kubernetesHostFromEnv(); k8sHost != "" {
			config.Host = k8sHost
		} else {
			return errNoSealosHost
		}
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return fmt.Errorf("failed to new client: %w", err)
	}
	discoveryClient, err := discovery.NewDiscoveryClientForConfig(config)
	if err != nil {
		return fmt.Errorf("failed to new discovery client: %w", err)
	}

	res, err := discoveryClient.RESTClient().Get().AbsPath("/readyz").DoRaw(context.Background())
	if err != nil {
		return fmt.Errorf("ping apiserver error: %w", err)
	}
	if string(res) != "ok" {
		return fmt.Errorf("ping apiserver is no ok: %s", string(res))
	}

	return checkResourceAccess(clientset, namespace, "get", "pods")
}

func checkResourceAccess(clientset *kubernetes.Clientset, namespace, verb, resource string) error {
	review := &authorizationapi.SelfSubjectAccessReview{
		Spec: authorizationapi.SelfSubjectAccessReviewSpec{
			ResourceAttributes: &authorizationapi.ResourceAttributes{
				Namespace: namespace,
				Verb:      verb,
				Group:     "",
				Version:   "v1",
				Resource:  resource,
			},
		},
	}
	resp, err := clientset.AuthorizationV1().SelfSubjectAccessReviews().Create(context.Background(), review, metav1.CreateOptions{})
	if err != nil {
		return err
	}
	if !resp.Status.Allowed {
		return errNoAuth
	}
	return nil
}

func isWhitelistedKubernetesHost(host string) bool {
	for _, item := range strings.Split(os.Getenv("WHITELIST_KUBERNETES_HOSTS"), ",") {
		if strings.TrimSpace(item) == host {
			return true
		}
	}
	return false
}

func kubernetesHostFromEnv() string {
	host, port := os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
	if host == "" || port == "" {
		return ""
	}
	return "https://" + net.JoinHostPort(host, port)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
