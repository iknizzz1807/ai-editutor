// utils/validation.ts - Input validation utilities

import { ValidationError } from '../types/api';
import { CreateUserDTO, UpdateUserDTO } from '../types/user';
import { RegisterData, ChangePasswordRequest } from '../types/auth';

export const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const PASSWORD_MIN_LENGTH = 8;
export const USERNAME_MIN_LENGTH = 3;
export const USERNAME_MAX_LENGTH = 30;
export const USERNAME_REGEX = /^[a-zA-Z0-9_-]+$/;

export interface ValidationResult {
  isValid: boolean;
  errors: ValidationError[];
}

export function validateEmail(email: string): ValidationError | null {
  if (!email) {
    return { field: 'email', message: 'Email is required', code: 'REQUIRED' };
  }
  if (!EMAIL_REGEX.test(email)) {
    return { field: 'email', message: 'Invalid email format', code: 'INVALID_FORMAT' };
  }
  return null;
}

export function validatePassword(password: string): ValidationError | null {
  if (!password) {
    return { field: 'password', message: 'Password is required', code: 'REQUIRED' };
  }
  if (password.length < PASSWORD_MIN_LENGTH) {
    return {
      field: 'password',
      message: `Password must be at least ${PASSWORD_MIN_LENGTH} characters`,
      code: 'TOO_SHORT',
    };
  }
  if (!/[A-Z]/.test(password)) {
    return {
      field: 'password',
      message: 'Password must contain at least one uppercase letter',
      code: 'MISSING_UPPERCASE',
    };
  }
  if (!/[a-z]/.test(password)) {
    return {
      field: 'password',
      message: 'Password must contain at least one lowercase letter',
      code: 'MISSING_LOWERCASE',
    };
  }
  if (!/[0-9]/.test(password)) {
    return {
      field: 'password',
      message: 'Password must contain at least one number',
      code: 'MISSING_NUMBER',
    };
  }
  return null;
}

export function validateUsername(username: string): ValidationError | null {
  if (!username) {
    return { field: 'username', message: 'Username is required', code: 'REQUIRED' };
  }
  if (username.length < USERNAME_MIN_LENGTH) {
    return {
      field: 'username',
      message: `Username must be at least ${USERNAME_MIN_LENGTH} characters`,
      code: 'TOO_SHORT',
    };
  }
  if (username.length > USERNAME_MAX_LENGTH) {
    return {
      field: 'username',
      message: `Username must be at most ${USERNAME_MAX_LENGTH} characters`,
      code: 'TOO_LONG',
    };
  }
  if (!USERNAME_REGEX.test(username)) {
    return {
      field: 'username',
      message: 'Username can only contain letters, numbers, underscores, and hyphens',
      code: 'INVALID_FORMAT',
    };
  }
  return null;
}

export function validateCreateUser(data: CreateUserDTO): ValidationResult {
  const errors: ValidationError[] = [];

  const emailError = validateEmail(data.email);
  if (emailError) errors.push(emailError);

  const usernameError = validateUsername(data.username);
  if (usernameError) errors.push(usernameError);

  const passwordError = validatePassword(data.password);
  if (passwordError) errors.push(passwordError);

  return { isValid: errors.length === 0, errors };
}

export function validateRegistration(data: RegisterData): ValidationResult {
  const errors: ValidationError[] = [];

  const emailError = validateEmail(data.email);
  if (emailError) errors.push(emailError);

  const usernameError = validateUsername(data.username);
  if (usernameError) errors.push(usernameError);

  const passwordError = validatePassword(data.password);
  if (passwordError) errors.push(passwordError);

  if (data.password !== data.confirmPassword) {
    errors.push({
      field: 'confirmPassword',
      message: 'Passwords do not match',
      code: 'PASSWORD_MISMATCH',
    });
  }

  if (!data.acceptTerms) {
    errors.push({
      field: 'acceptTerms',
      message: 'You must accept the terms and conditions',
      code: 'TERMS_NOT_ACCEPTED',
    });
  }

  return { isValid: errors.length === 0, errors };
}

// Q: How does this validation function handle edge cases like empty strings vs undefined?
export function validateChangePassword(data: ChangePasswordRequest): ValidationResult {
  const errors: ValidationError[] = [];

  if (!data.currentPassword) {
    errors.push({
      field: 'currentPassword',
      message: 'Current password is required',
      code: 'REQUIRED',
    });
  }

  const newPasswordError = validatePassword(data.newPassword);
  if (newPasswordError) {
    errors.push({ ...newPasswordError, field: 'newPassword' });
  }

  if (data.newPassword !== data.confirmPassword) {
    errors.push({
      field: 'confirmPassword',
      message: 'Passwords do not match',
      code: 'PASSWORD_MISMATCH',
    });
  }

  if (data.currentPassword === data.newPassword) {
    errors.push({
      field: 'newPassword',
      message: 'New password must be different from current password',
      code: 'SAME_PASSWORD',
    });
  }

  return { isValid: errors.length === 0, errors };
}
