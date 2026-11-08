<!-- SPDX-License-Identifier: GPL-3.0-or-later
License: GNU GPLv3 or later. See the license file in the project root for more information.
Copyright © 2021 - present Aleksey Hoffman. All rights reserved.
-->

<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { Loader2Icon, NetworkIcon, ServerIcon, Trash2Icon } from '@lucide/vue';
import { PageHomeLayout } from '@/layouts';
import { Button } from '@/components/ui/button';
import MountDialog from '@/modules/home/components/mount-dialog.vue';
import {
  getServerMountPathLabel,
  getServerSourceLabel,
  useNetworkServers,
} from '@/modules/network/composables/use-network-servers';
import { openNavigatorPath } from '@/utils/open-navigator-directory';
import type { NetworkServer } from '@/types/user-settings';

const { t } = useI18n();
const router = useRouter();
const { servers, removeServer, mountServer } = useNetworkServers();

const showConnectDialog = ref(false);
const connectingServerId = ref<string | null>(null);
const serverErrors = ref<Record<string, string>>({});

async function handleOpenServer(server: NetworkServer) {
  if (connectingServerId.value) {
    return;
  }

  connectingServerId.value = server.id;
  delete serverErrors.value[server.id];

  try {
    const mountPoint = await mountServer(server);
    openNavigatorPath(router, mountPoint, { resolvePath: true });
  }
  catch (mountError) {
    serverErrors.value[server.id] = String(mountError);
  }
  finally {
    connectingServerId.value = null;
  }
}

async function handleRemoveServer(server: NetworkServer) {
  delete serverErrors.value[server.id];
  await removeServer(server.id);
}
</script>

<template>
  <PageHomeLayout>
    <div class="network-page">
      <header class="network-page__header">
        <h1 class="network-page__title">
          {{ t('pages.network') }}
        </h1>
        <p class="network-page__description">
          {{ t('networkPage.description') }}
        </p>
      </header>

      <section class="network-page__section">
        <div class="network-page__section-header">
          <h2 class="network-page__section-title">
            {{ t('networkPage.savedServers') }}
          </h2>
          <Button
            size="sm"
            @click="showConnectDialog = true"
          >
            <NetworkIcon :size="14" />
            {{ t('networkPage.connectButton') }}
          </Button>
        </div>

        <p
          v-if="servers.length === 0"
          class="network-page__empty"
        >
          {{ t('networkPage.emptyServers') }}
        </p>

        <ul
          v-else
          class="network-page__list"
        >
          <li
            v-for="server in servers"
            :key="server.id"
            class="network-page__item"
          >
            <div class="network-page__server-row">
              <button
                type="button"
                class="network-page__server"
                :disabled="connectingServerId !== null"
                @click="handleOpenServer(server)"
              >
                <Loader2Icon
                  v-if="connectingServerId === server.id"
                  :size="20"
                  class="network-page__server-icon network-page__server-icon--spinning"
                />
                <ServerIcon
                  v-else
                  :size="20"
                  class="network-page__server-icon"
                />

                <span class="network-page__server-text">
                  <span class="network-page__server-name">
                    {{ server.mountName }}
                    <span class="network-page__server-protocol">{{ server.protocol }}</span>
                  </span>
                  <span class="network-page__server-meta">
                    {{ getServerSourceLabel(server) }}
                  </span>
                  <span class="network-page__server-meta">
                    {{ t('networkPage.mountedAt', { path: getServerMountPathLabel(server) }) }}
                  </span>
                </span>
              </button>

              <Button
                variant="ghost"
                size="icon"
                :title="t('networkPage.removeServer')"
                :aria-label="t('networkPage.removeServer')"
                @click="handleRemoveServer(server)"
              >
                <Trash2Icon :size="16" />
              </Button>
            </div>

            <p
              v-if="serverErrors[server.id]"
              class="network-page__error"
            >
              {{ serverErrors[server.id] }}
            </p>
          </li>
        </ul>

        <p class="network-page__hint">
          {{ t('networkPage.passwordNote') }}
        </p>
        <p class="network-page__hint">
          {{ t('networkPage.protocolsHint') }}
        </p>
      </section>
    </div>

    <MountDialog
      :open="showConnectDialog"
      initial-tab="network"
      @update:open="showConnectDialog = $event"
    />
  </PageHomeLayout>
</template>

<style>
.network-page {
  display: flex;
  flex-direction: column;
  padding: 0 16px 24px;
  margin-top: 52px;
  gap: 16px;
}

.network-page__header {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.network-page__title {
  color: hsl(var(--foreground));
  font-size: 2rem;
  font-weight: 600;
  letter-spacing: -0.025em;
}

.network-page__description {
  color: hsl(var(--muted-foreground));
}

.network-page__section {
  display: flex;
  max-width: 640px;
  flex-direction: column;
  gap: 12px;
}

.network-page__section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.network-page__section-title {
  color: hsl(var(--foreground));
  font-size: 1.125rem;
  font-weight: 600;
}

.network-page__list {
  display: flex;
  flex-direction: column;
  padding: 0;
  margin: 0;
  gap: 8px;
  list-style: none;
}

.network-page__item {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.network-page__server-row {
  display: flex;
  align-items: center;
  gap: 4px;
}

.network-page__server {
  display: flex;
  flex: 1;
  align-items: center;
  padding: 12px 14px;
  border: 1px solid hsl(var(--border));
  border-radius: var(--radius-lg);
  background-color: hsl(var(--card));
  color: hsl(var(--foreground));
  cursor: pointer;
  gap: 12px;
  text-align: start;
}

.network-page__server:hover:not(:disabled) {
  background-color: hsl(var(--muted));
}

.network-page__server:disabled {
  cursor: progress;
  opacity: 0.7;
}

.network-page__server-icon {
  flex-shrink: 0;
  color: hsl(var(--muted-foreground));
}

.network-page__server-icon--spinning {
  animation: network-page-spin 1s linear infinite;
}

@keyframes network-page-spin {
  to {
    transform: rotate(360deg);
  }
}

.network-page__server-text {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 2px;
}

.network-page__server-name {
  font-weight: 600;
}

.network-page__server-protocol {
  color: hsl(var(--muted-foreground));
  font-size: 0.75rem;
  font-weight: 400;
  margin-inline-start: 6px;
  text-transform: uppercase;
}

.network-page__server-meta {
  overflow: hidden;
  color: hsl(var(--muted-foreground));
  font-size: 0.8125rem;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.network-page__empty,
.network-page__hint {
  color: hsl(var(--muted-foreground));
  font-size: 0.875rem;
}

.network-page__error {
  padding: 8px 12px;
  border-radius: var(--radius-md);
  background-color: hsl(var(--destructive) / 15%);
  color: hsl(var(--destructive));
  font-size: 0.8125rem;
  overflow-wrap: break-word;
  user-select: text;
}
</style>
