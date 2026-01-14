// src/composables/useValidation.ts - Form validation composable

import { ref, reactive, computed } from 'vue';

type ValidatorFn = (value: any, formData?: any) => string | null;

type ValidationRules = Record<string, ValidatorFn[]>;

export const validators = {
  required(value: any, message = 'This field is required'): string | null {
    if (value === null || value === undefined || value === '') {
      return message;
    }
    if (Array.isArray(value) && value.length === 0) {
      return message;
    }
    return null;
  },

  email(value: string, message = 'Invalid email address'): string | null {
    if (!value) return null;
    const pattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return pattern.test(value) ? null : message;
  },

  minLength(min: number, message?: string): ValidatorFn {
    return (value: string) => {
      if (!value) return null;
      if (value.length < min) {
        return message || `Must be at least ${min} characters`;
      }
      return null;
    };
  },

  maxLength(max: number, message?: string): ValidatorFn {
    return (value: string) => {
      if (!value) return null;
      if (value.length > max) {
        return message || `Must be at most ${max} characters`;
      }
      return null;
    };
  },

  pattern(regex: RegExp, message = 'Invalid format'): ValidatorFn {
    return (value: string) => {
      if (!value) return null;
      return regex.test(value) ? null : message;
    };
  },

  // Q: How should we implement async validation (e.g., checking if username exists)?
  password(value: string): string | null {
    if (!value) return null;

    const requirements: string[] = [];

    if (value.length < 8) requirements.push('at least 8 characters');
    if (!/[A-Z]/.test(value)) requirements.push('one uppercase letter');
    if (!/[a-z]/.test(value)) requirements.push('one lowercase letter');
    if (!/\d/.test(value)) requirements.push('one digit');
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(value)) requirements.push('one special character');

    if (requirements.length > 0) {
      return `Password must contain: ${requirements.join(', ')}`;
    }
    return null;
  },

  match(fieldName: string, message?: string): ValidatorFn {
    return (value: any, formData: any) => {
      if (!value) return null;
      if (value !== formData?.[fieldName]) {
        return message || `Must match ${fieldName}`;
      }
      return null;
    };
  },

  username(value: string): string | null {
    if (!value) return null;

    if (value.length < 3) return 'Username must be at least 3 characters';
    if (value.length > 30) return 'Username must be at most 30 characters';
    if (!/^[a-zA-Z]/.test(value)) return 'Username must start with a letter';
    if (!/^[\w-]+$/.test(value)) {
      return 'Username can only contain letters, numbers, underscores, and hyphens';
    }

    const reserved = ['admin', 'root', 'system', 'api', 'www', 'mail', 'support'];
    if (reserved.includes(value.toLowerCase())) {
      return 'This username is reserved';
    }

    return null;
  },
};

export function useValidation(rules: ValidationRules) {
  const errors = reactive<Record<string, string[]>>({});

  const isValid = computed(() => {
    return Object.keys(errors).every((key) => errors[key].length === 0);
  });

  function validate(formData: Record<string, any>): boolean {
    // Clear previous errors
    Object.keys(errors).forEach((key) => {
      errors[key] = [];
    });

    let valid = true;

    for (const [field, fieldRules] of Object.entries(rules)) {
      const value = formData[field];
      const fieldErrors: string[] = [];

      for (const rule of fieldRules) {
        const error = rule(value, formData);
        if (error) {
          fieldErrors.push(error);
        }
      }

      if (fieldErrors.length > 0) {
        errors[field] = fieldErrors;
        valid = false;
      }
    }

    return valid;
  }

  function validateField(field: string, value: any, formData?: Record<string, any>): boolean {
    const fieldRules = rules[field];
    if (!fieldRules) return true;

    const fieldErrors: string[] = [];

    for (const rule of fieldRules) {
      const error = rule(value, formData);
      if (error) {
        fieldErrors.push(error);
      }
    }

    errors[field] = fieldErrors;
    return fieldErrors.length === 0;
  }

  function clearErrors(): void {
    Object.keys(errors).forEach((key) => {
      errors[key] = [];
    });
  }

  function clearFieldError(field: string): void {
    errors[field] = [];
  }

  return {
    errors,
    isValid,
    validate,
    validateField,
    clearErrors,
    clearFieldError,
  };
}
