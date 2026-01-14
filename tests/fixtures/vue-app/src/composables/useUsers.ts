// src/composables/useUsers.ts - Users composable

import { ref, reactive, computed, watch } from 'vue';
import { userService } from '@/services/userService';
import type { User, UserFilters, PaginatedResponse } from '@/types/user';

export interface UseUsersOptions {
  initialFilters?: UserFilters;
  autoFetch?: boolean;
  pageSize?: number;
}

// Q: How should we implement optimistic updates with rollback in Vue composables?
export function useUsers(options: UseUsersOptions = {}) {
  const { initialFilters = {}, autoFetch = true, pageSize = 20 } = options;

  const users = ref<User[]>([]);
  const selectedUser = ref<User | null>(null);
  const total = ref(0);
  const page = ref(1);
  const totalPages = ref(0);
  const isLoading = ref(false);
  const error = ref<string | null>(null);

  const filters = reactive<UserFilters>({ ...initialFilters });

  const hasNextPage = computed(() => page.value < totalPages.value);
  const hasPrevPage = computed(() => page.value > 1);

  async function fetchUsers(newFilters?: UserFilters): Promise<void> {
    isLoading.value = true;
    error.value = null;

    try {
      const response = await userService.getUsers({
        ...filters,
        ...newFilters,
        page: page.value,
        page_size: pageSize,
      });

      users.value = response.users;
      total.value = response.total;
      totalPages.value = response.totalPages;
    } catch (e) {
      error.value = (e as Error).message;
    } finally {
      isLoading.value = false;
    }
  }

  async function fetchUser(id: string): Promise<User | null> {
    isLoading.value = true;
    error.value = null;

    try {
      const user = await userService.getUser(id);
      selectedUser.value = user;
      return user;
    } catch (e) {
      error.value = (e as Error).message;
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  async function createUser(userData: Partial<User>): Promise<User> {
    isLoading.value = true;
    error.value = null;

    try {
      const user = await userService.createUser(userData);
      await fetchUsers(); // Refresh list
      return user;
    } catch (e) {
      error.value = (e as Error).message;
      throw e;
    } finally {
      isLoading.value = false;
    }
  }

  async function updateUser(id: string, userData: Partial<User>): Promise<User> {
    isLoading.value = true;
    error.value = null;

    // Optimistic update
    const originalUsers = [...users.value];
    const index = users.value.findIndex((u) => u.id === id);
    if (index !== -1) {
      users.value[index] = { ...users.value[index], ...userData };
    }

    try {
      const user = await userService.updateUser(id, userData);

      // Update in list with server response
      if (index !== -1) {
        users.value[index] = user;
      }

      // Update selected user if it's the same
      if (selectedUser.value?.id === id) {
        selectedUser.value = user;
      }

      return user;
    } catch (e) {
      // Rollback on error
      users.value = originalUsers;
      error.value = (e as Error).message;
      throw e;
    } finally {
      isLoading.value = false;
    }
  }

  async function deleteUser(id: string): Promise<void> {
    isLoading.value = true;
    error.value = null;

    // Optimistic update
    const originalUsers = [...users.value];
    users.value = users.value.filter((u) => u.id !== id);

    try {
      await userService.deleteUser(id);

      if (selectedUser.value?.id === id) {
        selectedUser.value = null;
      }

      total.value--;
    } catch (e) {
      // Rollback on error
      users.value = originalUsers;
      error.value = (e as Error).message;
      throw e;
    } finally {
      isLoading.value = false;
    }
  }

  async function searchUsers(query: string): Promise<User[]> {
    try {
      return await userService.searchUsers(query);
    } catch {
      return [];
    }
  }

  function setFilter(key: keyof UserFilters, value: any): void {
    (filters as any)[key] = value;
    page.value = 1;
  }

  function clearFilters(): void {
    Object.keys(filters).forEach((key) => {
      delete (filters as any)[key];
    });
    page.value = 1;
  }

  function nextPage(): void {
    if (hasNextPage.value) {
      page.value++;
    }
  }

  function prevPage(): void {
    if (hasPrevPage.value) {
      page.value--;
    }
  }

  function goToPage(pageNum: number): void {
    if (pageNum >= 1 && pageNum <= totalPages.value) {
      page.value = pageNum;
    }
  }

  function clearSelectedUser(): void {
    selectedUser.value = null;
  }

  function clearError(): void {
    error.value = null;
  }

  // Watch for filter/page changes
  watch([() => filters, page], () => {
    fetchUsers();
  }, { deep: true });

  // Initial fetch
  if (autoFetch) {
    fetchUsers();
  }

  return {
    // State
    users,
    selectedUser,
    total,
    page,
    totalPages,
    isLoading,
    error,
    filters,

    // Computed
    hasNextPage,
    hasPrevPage,

    // Actions
    fetchUsers,
    fetchUser,
    createUser,
    updateUser,
    deleteUser,
    searchUsers,

    // Pagination
    nextPage,
    prevPage,
    goToPage,

    // Filters
    setFilter,
    clearFilters,

    // Utilities
    clearSelectedUser,
    clearError,
  };
}
