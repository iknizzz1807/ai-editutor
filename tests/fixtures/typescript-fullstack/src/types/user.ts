// types/user.ts - Core user types used throughout the application

export type UserRole = 'admin' | 'moderator' | 'user' | 'guest';

export type UserStatus = 'active' | 'inactive' | 'suspended' | 'pending';

export interface UserAddress {
  street: string;
  city: string;
  state: string;
  country: string;
  zipCode: string;
}

export interface UserPreferences {
  theme: 'light' | 'dark' | 'system';
  language: string;
  notifications: {
    email: boolean;
    push: boolean;
    sms: boolean;
  };
  timezone: string;
}

export interface User {
  id: string;
  email: string;
  username: string;
  passwordHash: string;
  role: UserRole;
  status: UserStatus;
  profile: UserProfile;
  preferences: UserPreferences;
  addresses: UserAddress[];
  createdAt: Date;
  updatedAt: Date;
  lastLoginAt: Date | null;
}

export interface UserProfile {
  firstName: string;
  lastName: string;
  avatar: string | null;
  bio: string | null;
  phone: string | null;
  dateOfBirth: Date | null;
}

export interface CreateUserDTO {
  email: string;
  username: string;
  password: string;
  role?: UserRole;
  profile: Partial<UserProfile>;
}

export interface UpdateUserDTO {
  email?: string;
  username?: string;
  role?: UserRole;
  status?: UserStatus;
  profile?: Partial<UserProfile>;
  preferences?: Partial<UserPreferences>;
}

export interface UserResponse {
  id: string;
  email: string;
  username: string;
  role: UserRole;
  status: UserStatus;
  profile: UserProfile;
  createdAt: string;
}

export interface UserListResponse {
  users: UserResponse[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export interface UserFilters {
  role?: UserRole;
  status?: UserStatus;
  search?: string;
  createdAfter?: Date;
  createdBefore?: Date;
}
