<script lang="ts">
  // src/lib/components/LoginForm.svelte - Login form component

  import { authStore, isLoading, authError } from '$lib/stores/auth';
  import { validators, createFormValidator } from '$lib/utils/validation';
  import type { LoginCredentials } from '$lib/types';

  let form: LoginCredentials = {
    email: '',
    password: '',
  };

  let showPassword = false;
  let touched: Record<string, boolean> = {};

  const validator = createFormValidator({
    email: [validators.required, validators.email],
    password: [validators.required, validators.minLength(8)],
  });

  $: errors = validator.getErrors();

  function handleBlur(field: string) {
    touched[field] = true;
    validator.validateField(field, form[field as keyof LoginCredentials], form);
  }

  async function handleSubmit() {
    touched = { email: true, password: true };

    if (!validator.validate(form)) {
      return;
    }

    try {
      await authStore.login(form);
    } catch {
      // Error handled by store
    }
  }
</script>

<form on:submit|preventDefault={handleSubmit} class="login-form">
  <h2>Login</h2>

  {#if $authError}
    <div class="form-error">{$authError}</div>
  {/if}

  <div class="form-group">
    <label for="email">Email</label>
    <input
      id="email"
      type="email"
      placeholder="Enter your email"
      bind:value={form.email}
      on:blur={() => handleBlur('email')}
      class:is-invalid={touched.email && errors.email?.length}
    />
    {#if touched.email && errors.email?.length}
      <div class="field-error">{errors.email[0]}</div>
    {/if}
  </div>

  <div class="form-group">
    <label for="password">Password</label>
    <div class="password-input">
      <input
        id="password"
        type={showPassword ? 'text' : 'password'}
        placeholder="Enter your password"
        bind:value={form.password}
        on:blur={() => handleBlur('password')}
        class:is-invalid={touched.password && errors.password?.length}
      />
      <button
        type="button"
        on:click={() => (showPassword = !showPassword)}
        class="password-toggle"
      >
        {showPassword ? 'Hide' : 'Show'}
      </button>
    </div>
    {#if touched.password && errors.password?.length}
      <div class="field-error">{errors.password[0]}</div>
    {/if}
  </div>

  <button type="submit" disabled={$isLoading} class="btn btn--primary btn--block">
    {$isLoading ? 'Logging in...' : 'Login'}
  </button>

  <p class="login-form__footer">
    Don't have an account?
    <a href="/register">Register</a>
  </p>
</form>

<style>
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
