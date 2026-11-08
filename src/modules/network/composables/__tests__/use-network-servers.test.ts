// SPDX-License-Identifier: GPL-3.0-or-later
// License: GNU GPLv3 or later. See the license file in the project root for more information.
// Copyright © 2021 - present Aleksey Hoffman. All rights reserved.

import {
  beforeEach, describe, expect, it, vi,
} from 'vitest';
import { reactive } from 'vue';
import type { NetworkServer } from '@/types/user-settings';

const invokeMock = vi.hoisted(() => vi.fn());

const settingsState = vi.hoisted(() => ({
  value: null as unknown as {
    userSettings: { networkServers: unknown[] };
    set: (key: string, value: unknown) => Promise<void>;
  },
}));

vi.mock('@tauri-apps/api/core', () => ({
  invoke: invokeMock,
}));

vi.mock('@/stores/storage/user-settings', () => ({
  useUserSettingsStore: () => settingsState.value,
}));

import {
  getDefaultMountPath,
  getServerMountPathLabel,
  getServerSourceLabel,
  useNetworkServers,
} from '../use-network-servers';

function createDraft(overrides: Partial<Omit<NetworkServer, 'id'>> = {}): Omit<NetworkServer, 'id'> {
  return {
    protocol: 'sshfs',
    host: 'files.example.test',
    port: 22,
    username: 'root',
    remotePath: '/srv',
    mountName: 'files',
    mountPath: '',
    ...overrides,
  };
}

describe('useNetworkServers', () => {
  beforeEach(() => {
    invokeMock.mockReset();
    const state = reactive({ networkServers: [] as unknown[] });
    settingsState.value = {
      userSettings: state,
      set: async (_key, value) => {
        state.networkServers = value as unknown[];
      },
    };
  });

  it('uses ~/Remote/<name> as the default mount path label', () => {
    expect(getDefaultMountPath('files')).toBe('~/Remote/files');

    const server: NetworkServer = {
      ...createDraft(),
      id: '1',
    };
    expect(getServerMountPathLabel(server)).toBe('~/Remote/files');
    expect(getServerMountPathLabel({
      ...server,
      mountPath: '/mnt/custom',
    })).toBe('/mnt/custom');
  });

  it('describes the source as user@host:port path', () => {
    const server: NetworkServer = {
      ...createDraft(),
      id: '1',
    };
    expect(getServerSourceLabel(server)).toBe('root@files.example.test:22 /srv');
  });

  it('saves a server once and updates it instead of duplicating', async () => {
    const { servers, saveServer } = useNetworkServers();

    const first = await saveServer(createDraft());
    const second = await saveServer(createDraft({
      mountName: 'renamed',
      mountPath: '/mnt/x',
    }));

    expect(servers.value).toHaveLength(1);
    expect(second.id).toBe(first.id);
    expect(servers.value[0].mountName).toBe('renamed');
    expect(servers.value[0].mountPath).toBe('/mnt/x');

    await saveServer(createDraft({ remotePath: '/other' }));
    expect(servers.value).toHaveLength(2);
  });

  it('removes a server by id', async () => {
    const { servers, saveServer, removeServer } = useNetworkServers();
    const saved = await saveServer(createDraft());

    await removeServer(saved.id);

    expect(servers.value).toHaveLength(0);
  });

  it('mounts with a null mount_path and no password when none is given', async () => {
    invokeMock.mockResolvedValue('/home/user/Remote/files');
    const { mountServer } = useNetworkServers();

    const mountPoint = await mountServer({
      ...createDraft(),
      id: '1',
    });

    expect(mountPoint).toBe('/home/user/Remote/files');
    expect(invokeMock).toHaveBeenCalledWith('mount_network_share', {
      params: {
        protocol: 'sshfs',
        host: 'files.example.test',
        port: 22,
        username: 'root',
        password: null,
        remote_path: '/srv',
        mount_name: 'files',
        mount_path: null,
      },
    });
  });

  it('passes a custom mount path to the backend', async () => {
    invokeMock.mockResolvedValue('/mnt/custom');
    const { mountServer } = useNetworkServers();

    await mountServer({
      ...createDraft({ mountPath: ' /mnt/custom ' }),
      id: '1',
    });

    const call = invokeMock.mock.calls[0][1] as { params: { mount_path: string | null } };
    expect(call.params.mount_path).toBe('/mnt/custom');
  });
});
