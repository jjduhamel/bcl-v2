<script setup>
import useEthUtils from '~/composables/useEthUtils';
import userIcon from '~/assets/icons/bytesize/user.svg';
import robotIcon from '~/assets/icons/robot.svg';
import editIcon from '~/assets/icons/bytesize/edit.svg';
const { truncAddress, isAddress } = useEthUtils();

const emit = defineEmits([ 'register', 'update', 'suspend', 'resume', 'unregister', 'cancel' ]);

const props = defineProps({
  // Either a PlayerProfile ({ username, avatar, createdAt }) or a RobotProfile
  // (extends with owner/active/nickname + the AgentInfo stats); `owner` is the
  // RobotProfile-only field we use to discriminate.
  profile:   { type: Object,  default: () => ({}) },
  address:   { type: String,  default: '' },
  editable:  { type: Boolean, default: false },
  isEditing: { type: Boolean, default: false },
  loading:   { type: Boolean, default: false }
});

const isAgent = computed(() => !!props.profile?.owner);
const subjectAddress = computed(() => props.profile?.address ?? props.address);
const displayName = computed(() => isAgent.value ? (props.profile?.nickname ?? '')
                                                 : (props.profile?.username ?? ''));
const avatar = computed(() => props.profile?.avatar ?? '');

const isRegistered = computed(() => {
  if (isAgent.value) return !!props.profile?.owner;
  return (props.profile?.createdAt ?? 0) > 0;
});

const status = computed(() => {
  if (!isAgent.value) return isRegistered.value ? 'Registered' : 'Unregistered';
  if (!props.profile?.delegated) return 'Pending';
  if (!props.profile?.active) return 'Suspended';
  return 'Active';
});
const statusColor = computed(() => {
  if (!isAgent.value) return isRegistered.value ? 'green' : 'red';
  if (!props.profile?.delegated) return 'orange';
  if (!props.profile?.active) return 'red';
  return 'green';
});

const editing = ref(props.isEditing);
const submitting = ref(false);
const editName = ref(displayName.value);
const editAvatar = ref(avatar.value);

// Registering a new agent needs a typed-in agent address; player registration
// is keyed on the wallet address so only the name is required input.
const canSubmit = computed(() => {
  if (!editName.value.trim()) return false;
  if (props.isEditing && isAgent.value) return isAddress(subjectAddress.value);
  return true;
});

function startEdit() {
  editName.value = displayName.value;
  editAvatar.value = avatar.value;
  editing.value = true;
}

// Registering (opened editing) closes on cancel; updating reverts to view mode.
function cancelEdit() {
  if (props.isEditing) return emit('cancel');
  editName.value = displayName.value;
  editAvatar.value = avatar.value;
  editing.value = false;
}

function save() {
  submitting.value = true;
  if (props.isEditing) {
    emit('register', isAgent.value
      ? { robot: subjectAddress.value, nickname: editName.value, avatar: editAvatar.value }
      : { username: editName.value, avatar: editAvatar.value });
  } else {
    emit('update', { nickname: editName.value, avatar: editAvatar.value });
  }
}

// Stay on the editable form until the tx settles. A registration closes the
// parent modal; an update returns to read mode.
watch(() => props.loading, (loading) => {
  if (loading || !submitting.value) return;
  submitting.value = false;
  if (!props.isEditing) editing.value = false;
});

function copy(text) {
  navigator.clipboard.writeText(text);
}

// Generate a pseudo-random boolean from the address
const isWhiteAgent = computed(() => {
  const hash = ethers.utils.keccak256(props.address);
  const firstByte = parseInt(hash.slice(2, 4), 16);
  return firstByte % 2 === 0;
});
</script>

<template lang='pug'>
div
  div(class='my-4 py-3 flex justify-between items-center gap-1 border-b')
    div(class='basis-2/5 flex justify-center')
      img(class='h-12' src='~assets/pieces/merida/bN.svg' v-if='isAgent')
      img(class='h-12' src='~assets/pieces/merida/bK.svg' v-else)
    div(class='basis-3/5 flex flex-col gap-1')
      div(v-if='isAgent' class='flex items-center')
        img(class='h-5' :src='userIcon')
        div(class='flex-1 flex items-center justify-end gap-2')
          span {{ truncAddress(profile.owner, 5) }}
          button(type='button' class='contents border-none' @click='copy(profile.owner)')
            img(class='h-4' src='~assets/icons/bytesize/link.svg')
      div(class='flex items-center')
        img(class='h-5' :src='isAgent ? robotIcon : userIcon')
        div(class='flex-1 flex items-center justify-end gap-2')
          span {{ truncAddress(subjectAddress, 5) }}
          button(type='button' class='contents border-none' @click='copy(subjectAddress)')
            img(class='h-4' src='~assets/icons/bytesize/link.svg')
  div(class='flex justify-between')
    div(class='text-xl font-bold') {{ isAgent ? 'Agent' : 'Player' }} Profile
    button(
      v-if='isAgent && !editing && editable'
      type='button'
      class='border-none group'
      title='Edit'
      @click='startEdit'
      :disabled='loading'
    )
      img(class='h-4 opacity-50 group-hover:opacity-100' :src='editIcon')
  div(class='mt-2 flex items-center')
    div(class='flex-1') Name:
    div(class='flex-1 flex justify-end')
      input(v-if='editing' class='w-40' v-model='editName')
      span(v-else) {{ displayName || '—' }}
  div(class='mt-2 flex items-center')
    div(class='flex-1') Avatar:
    div(class='flex-1 flex justify-end')
      input(v-if='editing' class='w-40' v-model='editAvatar' placeholder='https://...')
      span(v-else) {{ avatar || '—' }}
  div(class='mt-2 flex items-center' v-if='!editing')
    div(class='flex-1') Status:
    div(class='flex-1 flex items-center justify-end gap-2')
      div(class='w-2 h-2 rounded-full' :style='{ backgroundColor: statusColor }')
      span {{ status }}
  div(id='form-controls')
    template(v-if='editing')
      button(type='button' :disabled='loading || !canSubmit' @click='save') {{ isEditing ? 'Register' : 'Save' }}
      button(type='button' :disabled='loading' @click='cancelEdit') Cancel
    template(v-else-if='isAgent && editable')
      button(
        type='button'
        :disabled='loading'
        @click='emit(profile.active ? "suspend" : "resume")'
      ) {{ profile.active ? 'Suspend' : 'Resume' }}
      button(type='button' :disabled='loading' @click='emit("unregister")') Unregister
</template>
