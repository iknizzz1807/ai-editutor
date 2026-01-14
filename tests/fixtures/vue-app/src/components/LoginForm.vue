<script setup lang="ts">
// src/components/LoginForm.vue - Login form component

import { ref, reactive } from 'vue';
import { useRouter } from 'vue-router';
import { useAuth } from '@/composables/useAuth';
import { useValidation, validators } from '@/composables/useValidation';

const router = useRouter();
const { login, isLoading, error } = useAuth();

const form = reactive({
  email: '',
  password: '',
});

const { validate, errors, isValid } = useValidation({
  email: [validators.required, validators.email],
  password: [validators.required, validators.minLength(8)],
});

const showPassword = ref(false);

async function handleSubmit() {
  if (!validate(form)) {
    return;
  }

  try {
    await login({ email: form.email, password: form.password });
    router.push('/');
  } catch {
    // Error handled by useAuth
  }
}
</script>

<template>
  <form @submit.prevent="handleSubmit" class="login-form">
    <h2>Login</h2>

    <div v-if="error" class="form-error">{{ error }}</div>

    <div class="form-group">
      <label for="email">Email</label>
      <input
        id="email"
        v-model="form.email"
        type="email"
        placeholder="Enter your email"
        :class="{ 'is-invalid': errors.email?.length }"
      />
      <div v-if="errors.email?.length" class="field-error">
        {{ errors.email[0] }}
      </div>
    </div>

    <div class="form-group">
      <label for="password">Password</label>
      <div class="password-input">
        <input
          id="password"
          v-model="form.password"
          :type="showPassword ? 'text' : 'password'"
          placeholder="Enter your password"
          :class="{ 'is-invalid': errors.password?.length }"
        />
        <button
          type="button"
          @click="showPassword = !showPassword"
          class="password-toggle"
        >
          {{ showPassword ? 'Hide' : 'Show' }}
        </button>
      </div>
      <div v-if="errors.password?.length" class="field-error">
        {{ errors.password[0] }}
      </div>
    </div>

    <button type="submit" :disabled="isLoading" class="btn btn--primary btn--block">
      {{ isLoading ? 'Logging in...' : 'Login' }}
    </button>

    <p class="login-form__footer">
      Don't have an account?
      <router-link to="/register">Register</router-link>
    </p>
  </form>
</template>

<style scoped>
.login-form {
  max-width: 400px;
  margin: 2rem auto;
  padding: 2rem;
  border: 1px solid #ddd;
  border-radius: 8px;
}

.form-group {
  margin-bottom: 1rem;
}

.form-group label {
  display: block;
  margin-bottom: 0.5rem;
}

.form-group input {
  width: 100%;
  padding: 0.5rem;
  border: 1px solid #ddd;
  border-radius: 4px;
}

.form-group input.is-invalid {
  border-color: #dc3545;
}

.field-error {
  color: #dc3545;
  font-size: 0.875rem;
  margin-top: 0.25rem;
}

.form-error {
  background: #f8d7da;
  color: #721c24;
  padding: 0.75rem;
  border-radius: 4px;
  margin-bottom: 1rem;
}

.password-input {
  display: flex;
  gap: 0.5rem;
}

.password-input input {
  flex: 1;
}

.login-form__footer {
  text-align: center;
  margin-top: 1rem;
}
</style>
