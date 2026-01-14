// src/app/services/user.service.ts - User management service

import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, BehaviorSubject, throwError } from 'rxjs';
import { tap, catchError, map, finalize } from 'rxjs/operators';
import {
  User,
  UserFilters,
  PaginatedResponse,
  UserRole,
  UserStatus,
} from '../models/user.model';

interface UsersState {
  users: User[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
  filters: UserFilters;
  isLoading: boolean;
  error: string | null;
}

// Q: How should we implement state management with RxJS for complex Angular apps without NgRx?
@Injectable({
  providedIn: 'root',
})
export class UserService {
  private readonly apiUrl = '/api/users';

  private stateSubject = new BehaviorSubject<UsersState>({
    users: [],
    total: 0,
    page: 1,
    pageSize: 20,
    totalPages: 0,
    filters: {},
    isLoading: false,
    error: null,
  });

  public state$ = this.stateSubject.asObservable();
  public users$ = this.state$.pipe(map((state) => state.users));
  public total$ = this.state$.pipe(map((state) => state.total));
  public page$ = this.state$.pipe(map((state) => state.page));
  public totalPages$ = this.state$.pipe(map((state) => state.totalPages));
  public isLoading$ = this.state$.pipe(map((state) => state.isLoading));
  public error$ = this.state$.pipe(map((state) => state.error));

  constructor(private http: HttpClient) {}

  private get state(): UsersState {
    return this.stateSubject.value;
  }

  private updateState(partial: Partial<UsersState>): void {
    this.stateSubject.next({ ...this.state, ...partial });
  }

  fetchUsers(): Observable<PaginatedResponse<User>> {
    this.updateState({ isLoading: true, error: null });

    let params = new HttpParams()
      .set('page', this.state.page.toString())
      .set('pageSize', this.state.pageSize.toString());

    Object.entries(this.state.filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        params = params.set(key, String(value));
      }
    });

    return this.http.get<PaginatedResponse<User>>(this.apiUrl, { params }).pipe(
      tap((response) => {
        this.updateState({
          users: response.data,
          total: response.total,
          totalPages: response.totalPages,
        });
      }),
      catchError((error) => {
        this.updateState({
          error: error.message || 'Failed to fetch users',
        });
        return throwError(() => error);
      }),
      finalize(() => {
        this.updateState({ isLoading: false });
      })
    );
  }

  getUser(id: string): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/${id}`);
  }

  createUser(data: {
    email: string;
    username: string;
    password: string;
    role?: UserRole;
    firstName?: string;
    lastName?: string;
  }): Observable<User> {
    return this.http.post<User>(this.apiUrl, data).pipe(
      tap((newUser) => {
        this.updateState({
          users: [newUser, ...this.state.users],
          total: this.state.total + 1,
        });
      })
    );
  }

  updateUser(
    id: string,
    data: {
      username?: string;
      role?: UserRole;
      status?: UserStatus;
      profile?: Partial<User['profile']>;
    }
  ): Observable<User> {
    return this.http.put<User>(`${this.apiUrl}/${id}`, data).pipe(
      tap((updatedUser) => {
        this.updateState({
          users: this.state.users.map((u) => (u.id === id ? updatedUser : u)),
        });
      })
    );
  }

  deleteUser(id: string): Observable<void> {
    const previousUsers = this.state.users;
    const previousTotal = this.state.total;

    // Optimistic update
    this.updateState({
      users: this.state.users.filter((u) => u.id !== id),
      total: this.state.total - 1,
    });

    return this.http.delete<void>(`${this.apiUrl}/${id}`).pipe(
      catchError((error) => {
        // Rollback on error
        this.updateState({
          users: previousUsers,
          total: previousTotal,
          error: error.message || 'Failed to delete user',
        });
        return throwError(() => error);
      })
    );
  }

  setFilter<K extends keyof UserFilters>(key: K, value: UserFilters[K]): void {
    this.updateState({
      filters: { ...this.state.filters, [key]: value },
      page: 1,
    });
    this.fetchUsers().subscribe();
  }

  clearFilters(): void {
    this.updateState({ filters: {}, page: 1 });
    this.fetchUsers().subscribe();
  }

  setPage(page: number): void {
    this.updateState({ page });
    this.fetchUsers().subscribe();
  }
}
