<script setup>
import pilotFaceUrl from 'dashboard/assets/images/pilot-face-only.svg';

defineProps({
  alt: { type: String, default: '' },
});
</script>

<template>
  <img
    :src="pilotFaceUrl"
    :alt="alt"
    :aria-hidden="alt ? undefined : 'true'"
    class="block object-contain"
  />
</template>
