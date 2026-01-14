// src/composables/useAuth.ts - Auth composable

import { ref, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { authService } from '@/services/authService';
import { useStorage } from './useStorage';
import type { User, LoginCredentials, RegisterData } from '@/types/user';

const user = ref<User | null>(null);
const isAuthenticated = ref(false);
const isLoading = ref(false);
const error = ref<string | null>(null);

// Q: How should we handle auth state synchronization across multiple browser tabs in Vue?
export function useAuth() {
  const router = useRouter();
  const { get: getToken, set: setToken, remove: removeToken } = useStorage();

  const isAdmin = computed(() => user.value?.role === 'admin');
  const isModerator = computed(() => user.value?.role === 'moderator' || isAdmin.value);

  async function login(credentials: LoginCredentials): Promise<User> {
    isLoading.value = true;
    error.value = null;

    try {
      const response = await authService.login(credentials);

      setToken('access_token', response.access_token);
      setToken('refresh_token', response.refresh_token);

      user.value = response.user;
      isAuthenticated.value = true;

      return response.user;
    } catch (e) {
      error.value = (e as Error).message;
      throw e;
    } finally {
      isLoading.value = false;
    }
  }

  async function register(data: RegisterData): Promise<User> {
    isLoading.value = true;
    error.value = null;

    try {
      const response = await authService.register(data);

      setToken('access_token', response.access_token);
      setToken('refresh_token', response.refresh_token);

      user.value = response.user;
      isAuthenticated.value = true;

      return response.user;
    } catch (e) {
      error.value = (e as Error).message;
      throw e;
    } finally {
      isLoading.value = false;
    }
  }

  async function logout(): Promise<void> {
    try {
      await authService.logout();
    } catch {
      // Ignore logout errors
    } finally {
      clearSession();
      router.push('/login');
    }
  }

  function clearSession(): void {
    removeToken('access_token');
    removeToken('refresh_token');
    user.value = null;
    isAuthenticated.value = false;
  }

  async function loadUser(): Promise<User | null> {
    const token = getToken('access_token');
    if (!token) {
      return null;
    }

    isLoading.value = true;

    try {
      const userData = await authService.getCurrentUser();
      user.value = userData;
      isAuthenticated.value = true;
      return userData;
    } catch {
      clearSession();
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  async function updateProfile(profileData: Partial<User>): Promise<User> {
    const updatedUser = await authService.updateProfile(profileData);
    user.value = updatedUser;
    return updatedUser;
  }

  async function changePassword(currentPassword: string, newPassword: string): Promise<void> {
    await authService.changePassword(currentPassword, newPassword);
  }

  function hasRole(role: string): boolean {
    return user.value?.role === role;
  }

  function hasAnyRole(roles: string[]): boolean {
    return roles.some((role) => hasRole(role));
  }

  // Initialize on first use
  if (!user.value && getToken('access_token')) {
    loadUser();
  }

  // Cross-tab synchronization
  watch(
    () => getToken('access_token'),
    (newToken, oldToken) => {
      if (!newToken && oldToken) {
        clearSession();
      } else if (newToken && !oldToken) {
        loadUser();
      }
    }
  );

  return {
    user,
    isAuthenticated,
    isLoading,
    error,
    isAdmin,
    isModerator,
    login,
    register,
    logout,
    loadUser,
    updateProfile,
    changePassword,
    hasRole,
    hasAnyRole,
    clearSession,
  };
}
