import { start, notify } from '@bugsnag/js';

export default defineNuxtPlugin(app => {
  const { bugsnagId } = useRuntimeConfig();
  start({ apiKey: bugsnagId });
  return {
    provide: {
      bugsnag: {
        notify
      }
    }
  };
});
