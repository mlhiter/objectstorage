import { ChevronDownIcon } from '@chakra-ui/icons';
import {
  Box,
  Button,
  Flex,
  Menu,
  MenuButton,
  MenuItem,
  MenuList,
  Portal,
  type ButtonProps,
  type BoxProps,
  useDisclosure,
  useOutsideClick
} from '@chakra-ui/react';
import type { IconProps } from '@chakra-ui/react';
import React, { forwardRef, useMemo, useRef } from 'react';
import ReactMarkdown from 'react-markdown';
import { extendTheme } from '@chakra-ui/react';

type MySelectProps = ButtonProps & {
  width?: string;
  height?: string;
  value?: string;
  placeholder?: string;
  list: {
    label: string | React.ReactNode;
    value: string;
  }[];
  onchange?: (val: string) => void;
  isInvalid?: boolean;
  boxStyle?: BoxProps;
};

const MySelectInner = (
  {
    placeholder,
    value,
    width = 'auto',
    height = '30px',
    list,
    onchange,
    isInvalid,
    boxStyle,
    ...props
  }: MySelectProps,
  selectRef: React.ForwardedRef<HTMLButtonElement>
) => {
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const selectWrapperRef = useRef<HTMLDivElement>(null);
  const menuListRef = useRef<HTMLDivElement>(null);
  const { isOpen, onOpen, onClose } = useDisclosure();

  useOutsideClick({
    ref: selectWrapperRef,
    handler: (event) => {
      if (menuListRef.current?.contains(event.target as Node)) return;
      onClose();
    }
  });

  const activeMenu = useMemo(() => {
    const foundItem = list.find((item) => item.value === value);
    if (!foundItem && value) {
      return {
        label: value,
        value
      };
    }
    return foundItem;
  }, [list, value]);

  return (
    <Menu autoSelect={false} isOpen={isOpen} onOpen={onOpen} onClose={onClose}>
      <Box
        ref={selectWrapperRef}
        position="relative"
        onClick={() => {
          isOpen ? onClose() : onOpen();
        }}
        {...boxStyle}
      >
        <MenuButton
          as={Button}
          rightIcon={<ChevronDownIcon />}
          width={width}
          height={height}
          ref={(node: HTMLButtonElement | null) => {
            buttonRef.current = node;
            if (typeof selectRef === 'function') {
              selectRef(node);
            } else if (selectRef) {
              selectRef.current = node;
            }
          }}
          display="flex"
          alignItems="center"
          justifyContent="center"
          border="1px solid #E8EBF0"
          borderRadius="md"
          fontSize="12px"
          fontWeight="400"
          variant="outline"
          _hover={{
            borderColor: 'brightBlue.300',
            bg: 'grayModern.50'
          }}
          _active={{
            transform: ''
          }}
          {...(isOpen
            ? {
                boxShadow: '0px 0px 0px 2.4px rgba(33, 155, 244, 0.15)',
                borderColor: 'brightBlue.500',
                bg: '#FFF'
              }
            : {
                bg: '#F7F8FA',
                borderColor: isInvalid ? 'red' : ''
              })}
          {...props}
        >
          <Flex justifyContent="flex-start">{activeMenu ? activeMenu.label : placeholder}</Flex>
        </MenuButton>

        <Portal>
          <MenuList
            ref={menuListRef}
            minW={(() => {
              const buttonWidth = buttonRef.current?.clientWidth;
              if (buttonWidth) {
                return `${buttonWidth}px !important`;
              }
              return `${props.w || width || 'auto'} !important`;
            })()}
            p="6px"
            borderRadius="base"
            border="1px solid #E8EBF0"
            boxShadow="0px 4px 10px 0px rgba(19, 51, 107, 0.10), 0px 0px 1px 0px rgba(19, 51, 107, 0.10)"
            zIndex={2000}
            overflow="overlay"
            maxH="300px"
          >
            {list.map((item) => (
              <MenuItem
                key={item.value}
                color={value === item.value ? 'brightBlue.600' : undefined}
                borderRadius="4px"
                _hover={{
                  bg: 'rgba(17, 24, 36, 0.05)',
                  color: 'brightBlue.600'
                }}
                p="6px"
                onClick={() => {
                  if (onchange && value !== item.value) {
                    onchange(item.value);
                  }
                  onClose();
                }}
              >
                <Box>{item.label}</Box>
              </MenuItem>
            ))}
          </MenuList>
        </Portal>
      </Box>
    </Menu>
  );
};

export const MySelect = React.memo(forwardRef(MySelectInner));

type CompatTabsProps = {
  list: { id: string; label: React.ReactNode }[];
  activeId: string;
  onChange: (id: string) => void;
};

export function Tabs({ list, activeId, onChange }: CompatTabsProps) {
  return (
    <Flex gap="6px" bg="grayModern.50" borderRadius="6px" p="4px">
      {list.map((item) => {
        const active = item.id === activeId;
        return (
          <Button
            key={item.id}
            variant="unstyled"
            flex={1}
            h="30px"
            minW="0"
            px="10px"
            borderRadius="4px"
            fontSize="12px"
            fontWeight={active ? 500 : 400}
            bg={active ? 'white' : 'transparent'}
            color={active ? 'grayModern.900' : 'grayModern.600'}
            boxShadow={active ? '0px 1px 2px 0px rgba(19, 51, 107, 0.08)' : 'none'}
            onClick={() => onChange(item.id)}
          >
            {item.label}
          </Button>
        );
      })}
    </Flex>
  );
}

export function YamlCode({ markdown }: { markdown: { children: string } }) {
  return (
    <Box
      as="pre"
      h="100%"
      overflow="auto"
      p="16px"
      m="0"
      bg="grayModern.50"
      color="grayModern.900"
      fontSize="12px"
      lineHeight="18px"
      whiteSpace="pre-wrap"
      fontFamily="Menlo, monospace"
    >
      <ReactMarkdown>{markdown.children}</ReactMarkdown>
    </Box>
  );
}

export const SortPolygonUpIcon = (props: IconProps) => (
  <Box as="svg" viewBox="0 0 8 5" fill="currentColor" {...props}>
    <path d="M4 0 8 5H0L4 0Z" />
  </Box>
);

export const SortPolygonDownIcon = (props: IconProps) => (
  <Box as="svg" viewBox="0 0 8 5" fill="currentColor" {...props}>
    <path d="M4 5 0 0h8L4 5Z" />
  </Box>
);

export const WarnTriangeIcon = (props: IconProps) => (
  <Box as="svg" viewBox="0 0 24 24" fill="none" {...props}>
    <path
      d="M10.3 3.9c.8-1.4 2.8-1.4 3.6 0l8 14A2.1 2.1 0 0 1 20 21H4a2.1 2.1 0 0 1-1.8-3.1l8.1-14Z"
      fill="currentColor"
      opacity="0.18"
    />
    <path
      d="M12 8v5m0 3h.01M10.3 3.9c.8-1.4 2.8-1.4 3.6 0l8 14A2.1 2.1 0 0 1 20 21H4a2.1 2.1 0 0 1-1.8-3.1l8.1-14Z"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </Box>
);

export const WebHostIcon = (props: IconProps) => (
  <Box as="svg" viewBox="0 0 24 24" fill="none" {...props}>
    <path
      d="M4 9h16M8 20h8M12 16v4M5 5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </Box>
);

const colors = {
  grayModern: {
    '05': 'rgba(17, 24, 36, 0.05)',
    1: 'rgba(17, 24, 36, 0.1)',
    15: 'rgba(17, 24, 36, 0.15)',
    25: '#FBFBFC',
    50: '#F7F8FA',
    100: '#F4F4F7',
    150: '#F0F1F6',
    200: '#E8EBF0',
    250: '#DFE2EA',
    300: '#C4CBD7',
    400: '#8A95A7',
    500: '#667085',
    600: '#485264',
    700: '#383F50',
    800: '#1D2532',
    900: '#111824'
  },
  grayIron: {
    600: '#475467'
  },
  brightBlue: {
    25: '#F9FDFE',
    50: '#F0FBFF',
    100: '#DBF3FF',
    200: '#BCE7FF',
    300: '#85CCFF',
    400: '#47B2FF',
    500: '#219BF4',
    600: '#0884DD',
    700: '#0770BC',
    800: '#005B9C',
    900: '#004B82'
  },
  warn: {
    600: '#DC6803'
  },
  boxShadowBlue: '0px 0px 0px 2.4px rgba(33, 155, 244, 0.15)',
  buttonBoxShadow:
    '0px 1px 2px 0px rgba(19, 51, 107, 0.05), 0px 0px 1px 0px rgba(19, 51, 107, 0.08)'
};

export const theme = extendTheme({
  colors,
  fonts: {
    body: '-apple-system, BlinkMacSystemFont, "PingFang SC", "Segoe UI", Helvetica, Arial, "Noto Sans SC", sans-serif',
    heading:
      '-apple-system, BlinkMacSystemFont, "PingFang SC", "Segoe UI", Helvetica, Arial, "Noto Sans SC", sans-serif',
    mono: 'Menlo, monospace'
  },
  fontWeights: {
    bold: 500
  },
  radii: {
    xs: '1px',
    sm: '2px',
    base: '4px',
    md: '6px',
    lg: '8px',
    xl: '12px',
    '2xl': '16px'
  },
  borders: {
    150: '1px solid #F0F1F6',
    200: '1px solid #E8EBF0',
    base: '1px solid #E8EBF0'
  },
  components: {
    Button: {
      variants: {
        solid: {
          bg: colors.grayModern[900],
          color: '#FFF',
          borderRadius: 'md',
          fontWeight: 500,
          boxShadow: colors.buttonBoxShadow,
          _hover: {
            opacity: '0.9',
            bg: colors.grayModern[900],
            _disabled: {
              bg: colors.grayModern[900],
              opacity: '0.4'
            }
          },
          _active: {
            bg: ''
          }
        },
        outline: {
          bg: '#FFF',
          borderRadius: 'md',
          fontWeight: 500,
          border: '1px solid',
          borderColor: 'grayModern.250',
          boxShadow: colors.buttonBoxShadow,
          color: 'grayModern.600',
          minW: '16px',
          minH: '16px',
          _hover: {
            opacity: '0.9',
            bg: 'rgba(33, 155, 244, 0.05)',
            color: 'brightBlue.700',
            borderColor: 'brightBlue.300'
          },
          _active: {
            bg: ''
          }
        },
        'white-bg-icon': {
          bg: '#FFF',
          color: 'grayModern.600',
          border: '1px solid',
          borderColor: 'grayModern.200',
          boxShadow: colors.buttonBoxShadow,
          _hover: {
            bg: 'grayModern.50',
            color: 'brightBlue.600'
          }
        },
        warningConfirm: {
          px: '19.5px',
          py: '8px',
          fontSize: '12px',
          fontWeight: '500',
          color: '#FFF',
          borderRadius: '6px',
          height: 'auto',
          bgColor: 'red.600',
          boxShadow: '0px 0px 1px 0px #13336B14, 0px 1px 2px 0px #13336B0D',
          _hover: {
            bgColor: 'rgba(217, 45, 32, 0.9)'
          }
        }
      }
    },
    Input: {
      variants: {
        outline: {
          field: {
            width: '300px',
            fontSize: '12px',
            fontWeight: 400,
            height: '32px',
            borderRadius: 'md',
            border: '1px solid',
            borderColor: '#E8EBF0',
            bg: colors.grayModern[50],
            _focusVisible: {
              borderColor: colors.brightBlue[500],
              boxShadow: colors.boxShadowBlue,
              bg: '#FFF',
              color: '#111824'
            },
            _disabled: {
              color: '#8A95A7',
              bg: '#FBFBFC',
              _hover: {}
            },
            _hover: {
              borderColor: colors.brightBlue[300],
              bg: colors.grayModern[50]
            },
            _invalid: {
              bg: '#FFF',
              borderColor: '#D92D20',
              boxShadow: '0px 0px 0px 2.4px rgba(217, 45, 32, 0.15)'
            },
            _placeholder: {
              color: '#667085',
              fontSize: '12px',
              fontWeight: 400,
              lineHeight: '16px'
            }
          }
        }
      },
      defaultProps: {
        size: 'md',
        variant: 'outline'
      }
    },
    Modal: {
      baseStyle: {
        header: {
          bg: '#FBFBFC',
          borderTopRadius: '10px',
          borderBottom: '1px solid #F4F4F7',
          fontSize: '16px',
          color: 'grayModern.900',
          fontWeight: '500',
          py: '11.5px',
          lineHeight: '24px'
        },
        closeButton: {
          fill: '#111824',
          svg: {
            width: '12px',
            height: '12px'
          }
        },
        dialog: {
          borderRadius: '10px'
        },
        body: {
          px: '36px',
          py: '24px'
        },
        footer: {
          px: '36px',
          pb: '24px',
          pt: '0px'
        }
      }
    }
  }
});
