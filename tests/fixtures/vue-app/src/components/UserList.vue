<script setup lang="ts">
// src/components/UserList.vue - User list component

import { computed } from 'vue';
import { useUsers } from '@/composables/useUsers';
import { useAuth } from '@/composables/useAuth';
import type { User, UserFilters } from '@/types/user';

interface Props {
  initialFilters?: UserFilters;
}

const props = withDefaults(defineProps<Props>(), {
  initialFilters: () => ({}),
});

const emit = defineEmits<{
  (e: 'view', user: User): void;
  (e: 'edit', user: User): void;
  (e: 'delete', user: User): void;
}>();

const {
  users,
  total,
  page,
  totalPages,
  isLoading,
  error,
  filters,
  hasNextPage,
  hasPrevPage,
  fetchUsers,
  deleteUser,
  setFilter,
  clearFilters,
  nextPage,
  prevPage,
  goToPage,
} = useUsers({ initialFilters: props.initialFilters });

const { isAdmin } = useAuth();

// Q: How should we implement infinite scroll with Vue 3 composition API?
const pageNumbers = computed(() => {
  const pages: (number | string)[] = [];
  for (let i = 1; i <= totalPages.value; i++) {
    if (
      i === 1 ||
      i === totalPages.value ||
      (i >= page.value - 2 && i <= page.value + 2)
    ) {
      pages.push(i);
    } else if (pages[pages.length - 1] !== '...') {
      pages.push('...');
    }
  }
  return pages;
});

function handleSearch(event: Event) {
  const target = event.target as HTMLInputElement;
  setFilter('search', target.value || undefined);
}

function handleRoleFilter(event: Event) {
  const target = event.target as HTMLSelectElement;
  setFilter('role', target.value || undefined);
}

function handleStatusFilter(event: Event) {
  const target = event.target as HTMLSelectElement;
  setFilter('status', target.value || undefined);
}

async function handleDelete(user: User) {
  if (confirm(`Are you sure you want to delete ${user.username}?`)) {
    try {
      await deleteUser(user.id);
    } catch (e) {
      // Error handled by composable
    }
  }
}
</script>

<template>
  <div class="user-list">
    <div class="user-list__header">
      <h2>Users ({{ total }})</h2>

      <div class="user-list__filters">
        <input
          type="search"
          placeholder="Search users..."
          :value="filters.search"
          @input="handleSearch"
          class="user-list__search"
        />

        <select @change="handleRoleFilter" class="user-list__filter">
          <option value="">All roles</option>
          <option value="admin">Admin</option>
          <option value="moderator">Moderator</option>
          <option value="user">User</option>
          <option value="guest">Guest</option>
        </select>

        <select @change="handleStatusFilter" class="user-list__filter">
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
          <option value="suspended">Suspended</option>
          <option value="pending">Pending</option>
        </select>

        <button @click="clearFilters" class="btn btn--secondary">
          Clear Filters
        </button>
      </div>
    </div>

    <div v-if="error" class="user-list__error">
      {{ error }}
      <button @click="fetchUsers">Retry</button>
    </div>

    <div v-if="isLoading" class="user-list__loading">Loading...</div>

    <table v-else-if="users.length > 0" class="user-table">
      <thead>
        <tr>
          <th>Name</th>
          <th>Email</th>
          <th>Role</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="user in users" :key="user.id">
          <td>{{ user.fullName || user.username }}</td>
          <td>{{ user.email }}</td>
          <td>
            <span :class="`badge badge--${user.role}`">{{ user.role }}</span>
          </td>
          <td>
            <span :class="`badge badge--${user.status}`">{{ user.status }}</span>
          </td>
          <td>
            <button @click="emit('view', user)" class="btn btn--sm">View</button>
            <template v-if="isAdmin">
              <button @click="emit('edit', user)" class="btn btn--sm">Edit</button>
              <button @click="handleDelete(user)" class="btn btn--sm btn--danger">
                Delete
              </button>
            </template>
          </td>
        </tr>
      </tbody>
    </table>

    <div v-else class="user-list__empty">No users found</div>

    <div v-if="totalPages > 1" class="pagination">
      <button :disabled="!hasPrevPage" @click="prevPage" class="pagination__btn">
        Previous
      </button>

      <template v-for="p in pageNumbers" :key="p">
        <span v-if="p === '...'" class="pagination__ellipsis">...</span>
        <button
          v-else
          :class="['pagination__btn', { active: p === page }]"
          @click="goToPage(p as number)"
        >
          {{ p }}
        </button>
      </template>

      <button :disabled="!hasNextPage" @click="nextPage" class="pagination__btn">
        Next
      </button>
    </div>
  </div>
</template>

<style scoped>
.user-list {
  padding: 1rem;
}

.user-list__header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.user-list__filters {
  display: flex;
  gap: 0.5rem;
}

.user-table {
  width: 100%;
  border-collapse: collapse;
}

.user-table th,
.user-table td {
  padding: 0.75rem;
  text-align: left;
  border-bottom: 1px solid #eee;
}

.pagination {
  display: flex;
  justify-content: center;
  gap: 0.25rem;
  margin-top: 1rem;
}

.pagination__btn {
  padding: 0.5rem 0.75rem;
}

.pagination__btn.active {
  background: #007bff;
  color: white;
}
</style>
