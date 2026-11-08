<!-- SPDX-License-Identifier: GPL-3.0-or-later
License: GNU GPLv3 or later. See the license file in the project root for more information.
Copyright © 2021 - present Aleksey Hoffman. All rights reserved.
-->

<script setup lang="ts">
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { NetworkIcon } from '@lucide/vue';
import { PageHomeLayout } from '@/layouts';
import { Button } from '@/components/ui/button';
import MountDialog from '@/modules/home/components/mount-dialog.vue';

const { t } = useI18n();
const showConnectDialog = ref(false);
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

      <section class="network-page__card">
        <NetworkIcon
          :size="32"
          class="network-page__icon"
        />
        <p class="network-page__hint">
          {{ t('networkPage.protocolsHint') }}
        </p>
        <Button @click="showConnectDialog = true">
          {{ t('networkPage.connectButton') }}
        </Button>
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

.network-page__card {
  display: flex;
  max-width: 480px;
  flex-direction: column;
  align-items: flex-start;
  padding: 20px;
  border: 1px solid hsl(var(--border));
  border-radius: var(--radius-lg);
  background-color: hsl(var(--card));
  gap: 12px;
}

.network-page__icon {
  color: hsl(var(--muted-foreground));
}

.network-page__hint {
  color: hsl(var(--muted-foreground));
  font-size: 0.875rem;
}
</style>
