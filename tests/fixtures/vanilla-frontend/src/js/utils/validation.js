// src/js/utils/validation.js - Form validation utilities

export const validators = {
  required(value, message = 'This field is required') {
    if (value === null || value === undefined || value === '') {
      return message;
    }
    if (Array.isArray(value) && value.length === 0) {
      return message;
    }
    return null;
  },

  email(value, message = 'Invalid email address') {
    if (!value) return null;
    const pattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return pattern.test(value) ? null : message;
  },

  minLength(min, message) {
    return (value) => {
      if (!value) return null;
      if (value.length < min) {
        return message || `Must be at least ${min} characters`;
      }
      return null;
    };
  },

  maxLength(max, message) {
    return (value) => {
      if (!value) return null;
      if (value.length > max) {
        return message || `Must be at most ${max} characters`;
      }
      return null;
    };
  },

  pattern(regex, message = 'Invalid format') {
    return (value) => {
      if (!value) return null;
      return regex.test(value) ? null : message;
    };
  },

  // Q: Should we implement real-time password strength feedback?
  password(value, message = 'Password does not meet requirements') {
    if (!value) return null;

    const errors = [];

    if (value.length < 8) {
      errors.push('at least 8 characters');
    }
    if (!/[A-Z]/.test(value)) {
      errors.push('one uppercase letter');
    }
    if (!/[a-z]/.test(value)) {
      errors.push('one lowercase letter');
    }
    if (!/\d/.test(value)) {
      errors.push('one digit');
    }
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(value)) {
      errors.push('one special character');
    }

    if (errors.length > 0) {
      return `Password must contain: ${errors.join(', ')}`;
    }
    return null;
  },

  match(fieldName, message) {
    return (value, formData) => {
      if (!value) return null;
      if (value !== formData[fieldName]) {
        return message || `Must match ${fieldName}`;
      }
      return null;
    };
  },

  phone(value, message = 'Invalid phone number') {
    if (!value) return null;
    const cleaned = value.replace(/[\s\-\(\)\.]/g, '');
    const pattern = /^\+?[0-9]{10,15}$/;
    return pattern.test(cleaned) ? null : message;
  },

  username(value, message = 'Invalid username') {
    if (!value) return null;

    if (value.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (value.length > 30) {
      return 'Username must be at most 30 characters';
    }
    if (!/^[a-zA-Z]/.test(value)) {
      return 'Username must start with a letter';
    }
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

export class FormValidator {
  constructor(rules) {
    this.rules = rules;
    this.errors = {};
  }

  validate(formData) {
    this.errors = {};
    let isValid = true;

    for (const [field, fieldRules] of Object.entries(this.rules)) {
      const value = formData[field];
      const fieldErrors = [];

      for (const rule of fieldRules) {
        const error = typeof rule === 'function' ? rule(value, formData) : null;
        if (error) {
          fieldErrors.push(error);
        }
      }

      if (fieldErrors.length > 0) {
        this.errors[field] = fieldErrors;
        isValid = false;
      }
    }

    return isValid;
  }

  getErrors() {
    return this.errors;
  }

  getFieldErrors(field) {
    return this.errors[field] || [];
  }

  hasErrors() {
    return Object.keys(this.errors).length > 0;
  }
}

export function getPasswordStrength(password) {
  if (!password) return { score: 0, label: 'None', color: 'gray' };

  let score = 0;

  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  if (/[A-Z]/.test(password)) score++;
  if (/[a-z]/.test(password)) score++;
  if (/\d/.test(password)) score++;
  if (/[!@#$%^&*(),.?":{}|<>]/.test(password)) score += 2;

  const levels = [
    { min: 0, label: 'Weak', color: 'red' },
    { min: 4, label: 'Fair', color: 'orange' },
    { min: 6, label: 'Strong', color: 'blue' },
    { min: 8, label: 'Very Strong', color: 'green' },
  ];

  const level = levels.reverse().find((l) => score >= l.min) || levels[0];

  return { score, ...level };
}
