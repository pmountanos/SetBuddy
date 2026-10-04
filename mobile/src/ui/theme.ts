import { useColorScheme } from 'react-native';

const light = {
  background: '#F2F2F7',
  card: '#FFFFFF',
  text: '#111111',
  secondary: '#6B6B70',
  tertiary: '#A0A0A6',
  border: '#D8D8DD',
  accent: '#0A6CFF',
  onAccent: '#FFFFFF',
  danger: '#D92D20',
  /** Last session's values shown as a reference while logging. */
  reference: '#E6730D',
  onReference: '#FFFFFF',
  /** Values the user has entered for today. */
  entered: '#000000',
  onEntered: '#FFFFFF',
  scrim: 'rgba(0,0,0,0.4)',
};

const dark: typeof light = {
  background: '#000000',
  card: '#1C1C1E',
  text: '#F5F5F7',
  secondary: '#A0A0A6',
  tertiary: '#6B6B70',
  border: '#38383A',
  accent: '#4C9AFF',
  onAccent: '#FFFFFF',
  danger: '#FF6B5E',
  reference: '#E6730D',
  onReference: '#FFFFFF',
  entered: '#F2F2F2',
  onEntered: '#000000',
  scrim: 'rgba(0,0,0,0.6)',
};

export type Theme = typeof light;

export function useTheme(): Theme {
  return useColorScheme() === 'dark' ? dark : light;
}
