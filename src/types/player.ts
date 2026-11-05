export interface PlayerState {
  title: string | null; artist: string | null; album: string | null; playbackRate: number; artworkUrl: string | null;
  duration: number | null; currentTime: number | null;
  isAd: boolean; isPlaying: boolean; canSeek: boolean; canNext: boolean; canPrevious: boolean;
}
export type PlayerCommand = { type: 'play' | 'pause' | 'toggle' | 'next' | 'previous' } | { type: 'seek'; time: number };
