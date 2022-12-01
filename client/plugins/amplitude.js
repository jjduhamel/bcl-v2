import {
  init,
  track,
  setUserId,
  setGroup,
  reset
} from '@amplitude/analytics-browser';

export default defineNuxtPlugin(app => {
  const { amplitudeId } = useRuntimeConfig();
  init(amplitudeId);
  return {
    provide: {
      amplitude: {
        track,
        setUserId,
        setGroup,
        reset
      }
    }
  };
});
