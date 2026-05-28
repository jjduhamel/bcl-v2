<script setup>
import useEthUtils from '~/composables/useEthUtils';
import userIcon from '~/assets/icons/bytesize/user.svg';
import robotIcon from '~/assets/icons/robot.svg';
import editIcon from '~/assets/icons/bytesize/edit.svg';
const { truncAddress, isAddress } = useEthUtils();

const emit = defineEmits([ 'register', 'update', 'suspend', 'unregister', 'cancel' ]);

const props = defineProps({
  isEditing:  { type: Boolean, default: false },
  address:    { type: String,  default: '' },
  owner:      { type: String,  default: '' },
  nickname:   { type: String,  default: '' },
  avatar:     { type: String,  default: '' },
  active:     { type: Boolean, default: false },
  delegated:  { type: Boolean, default: false },
  games:      { type: Number,  default: 0 },
  wins:       { type: Number,  default: 0 },
  losses:     { type: Number,  default: 0 },
  draws:      { type: Number,  default: 0 },
  loading:    { type: Boolean, default: false }
});

const status = computed(() => {
  if (!props.delegated) return 'Pending';
  if (!props.active) return 'Suspended';
  return 'Active';
});

const statusColor = computed(() => {
  if (!props.delegated) return 'orange';
  if (!props.active) return 'red';
  return 'green';
});

const validAddress = computed(() => isAddress(props.address));

const editing = ref(props.isEditing);
const submitting = ref(false);
const editNickname = ref(props.nickname);
const editAvatar = ref(props.avatar);

// Registering requires a valid agent address and a nickname.
const canSubmit = computed(() =>
  !props.isEditing || (validAddress.value && !!editNickname.value.trim())
);

function startEdit() {
  editNickname.value = props.nickname;
  editAvatar.value = props.avatar;
  editing.value = true;
}

// Registering (opened editing) closes on cancel; editing an existing agent reverts to the view.
function cancelEdit() {
  if (props.isEditing) return emit('cancel');
  editNickname.value = props.nickname;
  editAvatar.value = props.avatar;
  editing.value = false;
}

function save() {
  submitting.value = true;
  if (props.isEditing) emit('register', { robot: props.address, nickname: editNickname.value, avatar: editAvatar.value });
  else emit('update', { nickname: editNickname.value, avatar: editAvatar.value });
}

// Stay on the editable form until the tx settles (block mined). On success the
// parent closes a registration modal; an update then returns to the read view.
watch(() => props.loading, (loading) => {
  if (loading || !submitting.value) return;
  submitting.value = false;
  if (!props.isEditing) editing.value = false;
});

function copy(text) {
  navigator.clipboard.writeText(text);
}
</script>

<template lang='pug'>
div
  div(class='my-4 py-3 flex justify-between items-center gap-6 border-b')
    div(class='mx-2 p-2 border-2 rounded-full')
      img(class='h-10' :src='robotIcon')
    div(class='flex-1 flex flex-col gap-1')
      div(class='flex items-center')
        img(class='h-5' :src='userIcon')
        div(class='flex-1 flex items-center justify-end gap-2')
          span {{ truncAddress(owner, 5) }}
          button(type='button' class='contents border-none' @click='copy(owner)')
            img(class='h-4' src='~assets/icons/bytesize/link.svg')
      div(class='flex items-center')
        img(class='h-5' :src='robotIcon')
        div(class='flex-1 flex items-center justify-end gap-2')
          span {{ truncAddress(address, 5) }}
          button(type='button' class='contents border-none' @click='copy(address)')
            img(class='h-4' src='~assets/icons/bytesize/link.svg')
  div(class='flex justify-between')
    div(class='text-xl font-bold') Agent Details
    button(
      type='button'
      v-if='!editing'
      class='border-none group'
      title='Edit'
      @click='startEdit'
      :disabled='loading'
    )
      img(class='h-4 opacity-50 group-hover:opacity-100' :src='editIcon')
  div(class='mt-2 flex items-center')
    div(class='flex-1') Nickname:
    div(class='flex-1 flex justify-end')
      input(v-if='editing' class='w-40' v-model='editNickname')
      span(v-else) {{ nickname }}
  div(class='mt-2 flex items-center')
    div(class='flex-1') Avatar:
    div(class='flex-1 flex justify-end')
      input(v-if='editing' class='w-40' v-model='editAvatar' placeholder='https://...')
      span(v-else) {{ avatar || '—' }}
  div(class='mt-4 border-t pt-2 px-2 text-sm' v-if='!editing')
    div(class='mt-.5 flex items-center')
      div(class='flex-1') Status:
      div(class='flex-1 flex items-center justify-end gap-2')
        div(class='w-2 h-2 rounded-full' :style='{ backgroundColor: statusColor }')
        span {{ status }}
    div(class='mt-.5 flex items-center')
      div(class='flex-1') Games:
      div(class='flex-1 flex justify-end') {{ games }}
    div(class='mt-.5 flex items-center')
      div(class='flex-1') Wins:
      div(class='flex-1 flex justify-end') {{ wins }}
    div(class='mt-.5 flex items-center')
      div(class='flex-1') Losses:
      div(class='flex-1 flex justify-end') {{ losses }}
    div(class='mt-.5 flex items-center')
      div(class='flex-1') Draws:
      div(class='flex-1 flex justify-end') {{ draws }}
  div(id='form-controls')
    template(v-if='editing')
      button(type='button' :disabled='loading || !canSubmit' @click='save') {{ isEditing ? 'Register' : 'Save' }}
      button(type='button' :disabled='loading' @click='cancelEdit') Cancel
    template(v-else)
      button(type='button' :disabled='loading' @click='emit("suspend")') {{ active ? 'Suspend' : 'Unsuspend' }}
      button(type='button' :disabled='loading' @click='emit("unregister")') Unregister
</template>
