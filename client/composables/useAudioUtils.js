export default function() {
  function audioClip(clip) {
    // TODO load from assets
    //return new Audio(`~assets/audio/nes/${clip}.mp3`);
    return new Audio(`/audio/${clip}.mp3`);
  }

  function playAudioClip(clip) {
    audioClip(clip).play();
  }

  return {
    audioClip,
    playAudioClip
  };
}
