// src/lib/utils/validation.ts - Form validation utilities

export type ValidatorFn = (value: unknown, formData?: Record<string, unknown>) => string | null;

export const validators = {
  required(value: unknown, message = 'This field is required'): string | null {
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
    return (value: unknown) => {
      if (!value || typeof value !== 'string') return null;
      if (value.length < min) {
        return message || `Must be at least ${min} characters`;
      }
      return null;
    };
  },

  maxLength(max: number, message?: string): ValidatorFn {
    return (value: unknown) => {
      if (!value || typeof value !== 'string') return null;
      if (value.length > max) {
        return message || `Must be at most ${max} characters`;
      }
      return null;
    };
  },

  pattern(regex: RegExp, message = 'Invalid format'): ValidatorFn {
    return (value: unknown) => {
      if (!value || typeof value !== 'string') return null;
      return regex.test(value) ? null : message;
    };
  },

  // Q: How should we implement debounced async validation (like username availability check) with Svelte actions?
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
    return (value: unknown, formData?: Record<string, unknown>) => {
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

export interface ValidationResult {
  isValid: boolean;
  errors: Record<string, string[]>;
}

export function validate(
  formData: Record<string, unknown>,
  rules: Record<string, ValidatorFn[]>
): ValidationResult {
  const errors: Record<string, string[]> = {};
  let isValid = true;

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
      isValid = false;
    }
  }

  return { isValid, errors };
}

export function createFormValidator(rules: Record<string, ValidatorFn[]>) {
  let errors: Record<string, string[]> = {};

  return {
    validate(formData: Record<string, unknown>): boolean {
      const result = validate(formData, rules);
      errors = result.errors;
      return result.isValid;
    },

    validateField(field: string, value: unknown, formData?: Record<string, unknown>): boolean {
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
    },

    getErrors(): Record<string, string[]> {
      return errors;
    },

    getFieldError(field: string): string | null {
      return errors[field]?.[0] || null;
    },

    clearErrors(): void {
      errors = {};
    },

    clearFieldError(field: string): void {
      delete errors[field];
    },
  };
}
