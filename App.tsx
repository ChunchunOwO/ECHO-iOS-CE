import { useEffect, useState, type ReactElement } from 'react';
import { StyleSheet } from 'react-native';
import { EchoNativeAppView } from 'echo-audio-dsp';
import { loadSavedConnection } from './src/storage/connectionStore';
import { loadSavedLocalMusicState } from './src/storage/localMusicStore';
import { loadPowerampRemoteState } from './src/storage/powerampRemoteStore';
import { loadSavedSettings } from './src/storage/settingsStore';
import { loadNeteaseSession, loadStreamingPreferences } from './src/storage/streamingStore';

const defaultEchoConnection = {
  host: '',
  name: 'PC ECHO',
  port: 26789,
  scheme: 'http' as const,
  token: '',
};

const defaultPowerampConnection = {
  host: '',
  name: 'Poweramp',
  port: 27806,
  scheme: 'http' as const,
  token: '',
};

function NativeEchoApp(): ReactElement {
  const [migrationPayload, setMigrationPayload] = useState('');

  useEffect(() => {
    let mounted = true;
    void Promise.all([
      loadSavedConnection(),
      loadSavedSettings(),
      loadSavedLocalMusicState(),
      loadPowerampRemoteState(),
      loadNeteaseSession(),
      loadStreamingPreferences(),
    ]).then(([echo, settings, local, poweramp, netease, streaming]) => {
      if (!mounted) return;
      const audioTags = settings.audioTagVisibility;
      setMigrationPayload(JSON.stringify({
        neteaseCookie: netease?.cookie ?? '',
        state: {
          echoConnection: {
            ...(echo ?? defaultEchoConnection),
            enabled: settings.echoConnectionEnabled === true && echo !== null,
          },
          favoriteTrackKeys: [
            ...local.favoriteTrackIds.map((id) => `local:${id}`),
            ...local.echoFavoriteTrackIds.map((id) => `echo:${id}`),
            ...poweramp.favoriteTrackIds.map((id) => `remote:${id}`),
          ],
          playlists: local.playlists,
          powerampConnection: {
            ...(poweramp.connection ?? defaultPowerampConnection),
            enabled: settings.powerampRemoteEnabled === true && poweramp.connection !== null,
          },
          queueTrackKeys: local.queueTrackIds.map((id) => `local:${id}`),
          recentTrackKeys: [
            ...local.recentTrackIds.map((id) => `local:${id}`),
            ...local.echoRecentTrackIds.map((id) => `echo:${id}`),
            ...poweramp.recentTrackIds.map((id) => `remote:${id}`),
          ],
          settings: {
            artworkBackgroundEnabled: settings.artworkBackgroundEnabled ?? true,
            autoOpenLyricsForLocalTracks: settings.autoOpenLyricsForLocalTracks ?? true,
            autoQueueImportedLocalTracks: settings.autoQueueImportedLocalTracks ?? false,
            audioTagVisibility: {
              bitDepth: audioTags?.quality ?? true,
              bitrate: audioTags?.bitrate ?? true,
              codec: audioTags?.quality ?? true,
              duration: audioTags?.duration ?? true,
              output: audioTags?.output ?? true,
              sampleRate: audioTags?.quality ?? true,
              source: audioTags?.source ?? true,
              streamable: audioTags?.streamability ?? true,
            },
            confirmBeforeDeletingLocalTracks: settings.confirmBeforeDeletingLocalTracks ?? true,
            darkModeEnabled: settings.darkModeEnabled ?? false,
            defaultLibrarySource: settings.defaultLibrarySource ?? 'all',
            defaultLocalLibraryView: settings.defaultLocalLibraryView ?? 'songs',
            defaultPage: settings.defaultPage ?? 'control',
            eqGains: settings.eqGains ?? Array(10).fill(0),
            eqPreset: settings.eqPreset ?? 'flat',
            externalDataSelectionMode: settings.externalDataSelectionMode ?? 'ask',
            externalMetadataEnabled: settings.externalMetadataSearchEnabled ?? false,
            externalMetadataSkipExisting: settings.externalMetadataSkipExisting ?? true,
            followSystemAppearance: settings.followSystemAppearance ?? true,
            language: settings.appLanguage ?? 'zh',
            lrcApiExternalDataEnabled: settings.lrcApiExternalDataEnabled ?? false,
            lrclibExternalDataEnabled: settings.lrclibExternalDataEnabled ?? true,
            loudnessEnabled: settings.loudnessNormalizationEnabled ?? false,
            neteaseAccessMode: settings.neteaseAccessMode ?? 'direct',
            neteaseApiBaseUrl: netease?.apiBaseUrl || streaming.apiBaseUrl || 'https://music.163.com',
            neteaseExternalDataEnabled: settings.neteaseExternalDataEnabled ?? true,
            repeatOne: false,
            showArtworkGlow: settings.showArtworkGlow ?? true,
            showPowerampRemote: settings.showPowerampRemoteConnection ?? true,
          },
        },
        streamingFavoritePlaylistIds: streaming.favoritePlaylistIds,
        streamingPinnedPlaylistIds: streaming.pinnedPlaylistIds,
      }));
    }).catch(() => undefined);
    return () => { mounted = false; };
  }, []);

  return <EchoNativeAppView migrationPayload={migrationPayload} style={styles.root} />;
}

export default function App(): ReactElement {
  return <NativeEchoApp />;
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});
