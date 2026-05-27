import { Authority } from '@/consts';
import { BackgroundProps, ColorProps, Flex } from '@chakra-ui/react';
import { useTranslation } from 'next-i18next';

export default function AuthorityTips({ authority }: { authority: Authority }) {
  const { t } = useTranslation('bucket');
  const style: Record<Authority, ColorProps & BackgroundProps> = {
    [Authority.readonly]: {
      color: 'adora.600',
      bgColor: 'adora.50'
    },
    [Authority.private]: {
      color: 'brightBlue.600',
      bgColor: 'brightBlue.50'
    },
    [Authority.readwrite]: {
      color: 'teal.700',
      bgColor: 'teal.50'
    }
  };
  const label: Record<Authority, string> = {
    [Authority.readonly]: t('sharedBucketReadLabel'),
    [Authority.private]: t('privateBucketLabel'),
    [Authority.readwrite]: t('sharedBucketReadWriteLabel')
  };
  return (
    <Flex
      px="8px"
      py="4px"
      borderRadius={'4px'}
      {...style[authority]}
      fontSize={'11px'}
    >
      {label[authority]}
    </Flex>
  );
}
