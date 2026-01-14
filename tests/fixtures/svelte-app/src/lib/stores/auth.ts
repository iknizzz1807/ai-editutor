// src/lib/stores/auth.ts - Auth store with Svelte stores

import { writable, derived, get } from 'svelte/store';
import { browser } from '$app/environment';
import { goto } from '$app/navigation';
import { authService } from '$lib/services/authService';
import type { User, LoginCredentials, RegisterData } from '$lib/types';

interface AuthState {
  user: User | null;
  isLoading: boolean;
  error: string | null;
  isInitialized: boolean;
}

const initialState: AuthState = {
  user: null,
  isLoading: false,
  error: null,
  isInitialized: false,
};

function createAuthStore() {
  const { subscribe, set, update } = writable<AuthState>(initialState);

  // Q: How should we handle hydration mismatch when auth state differs between SSR and client in SvelteKit?
  async function initialize(): Promise<void> {
    if (!browser) return;

    const accessToken = localStorage.getItem('accessToken');
    if (!accessToken) {
      update((state) => ({ ...state, isInitialized: true }));
      return;
    }

    try {
      update((state) => ({ ...state, isLoading: true }));
      const user = await authService.getCurrentUser();
      update((state) => ({
        ...state,
        user,
        isLoading: false,
        isInitialized: true,
      }));
    } catch {
      localStorage.removeItem('accessToken');
      localStorage.removeItem('refreshToken');
      update((state) => ({
        ...state,
        user: null,
        isLoading: false,
        isInitialized: true,
      }));
    }
  }

  async function login(credentials: LoginCredentials): Promise<void> {
    update((state) => ({ ...state, isLoading: true, error: null }));

    try {
      const response = await authService.login(credentials);

      if (browser) {
        localStorage.setItem('accessToken', response.accessToken);
        localStorage.setItem('refreshToken', response.refreshToken);
      }

      update((state) => ({
        ...state,
        user: response.user,
        isLoading: false,
      }));

      await goto('/');
    } catch (error) {
      update((state) => ({
        ...state,
        isLoading: false,
        error: error instanceof Error ? error.message : 'Login failed',
      }));
      throw error;
    }
  }

  async function register(data: RegisterData): Promise<void> {
    update((state) => ({ ...state, isLoading: true, error: null }));

    try {
      const response = await authService.register(data);

      if (browser) {
        localStorage.setItem('accessToken', response.accessToken);
        localStorage.setItem('refreshToken', response.refreshToken);
      }

      update((state) => ({
        ...state,
        user: response.user,
        isLoading: false,
      }));

      await goto('/');
    } catch (error) {
      update((state) => ({
        ...state,
        isLoading: false,
        error: error instanceof Error ? error.message : 'Registration failed',
      }));
      throw error;
    }
  }

  async function logout(): Promise<void> {
    try {
      await authService.logout();
    } finally {
      if (browser) {
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
      }
      set(initialState);
      await goto('/login');
    }
  }

  function clearError(): void {
    update((state) => ({ ...state, error: null }));
  }

  return {
    subscribe,
    initialize,
    login,
    register,
    logout,
    clearError,
  };
}

export const authStore = createAuthStore();

export const user = derived(authStore, ($auth) => $auth.user);
export const isAuthenticated = derived(authStore, ($auth) => !!$auth.user);
export const isLoading = derived(authStore, ($auth) => $auth.isLoading);
export const authError = derived(authStore, ($auth) => $auth.error);
export const isAdmin = derived(authStore, ($auth) => $auth.user?.role === 'admin');
export const isInitialized = derived(authStore, ($auth) => $auth.isInitialized);
