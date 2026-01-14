// src/app/services/auth.service.ts - Authentication service

import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable, throwError } from 'rxjs';
import { tap, catchError, map } from 'rxjs/operators';
import { Router } from '@angular/router';
import {
  User,
  LoginCredentials,
  RegisterData,
  AuthResponse,
} from '../models/user.model';

// Q: How should we implement silent token refresh with Angular interceptors when multiple requests fail simultaneously?
@Injectable({
  providedIn: 'root',
})
export class AuthService {
  private readonly apiUrl = '/api/auth';
  private currentUserSubject = new BehaviorSubject<User | null>(null);
  private isRefreshing = false;
  private refreshTokenSubject = new BehaviorSubject<string | null>(null);

  public currentUser$ = this.currentUserSubject.asObservable();
  public isAuthenticated$ = this.currentUser$.pipe(map((user) => !!user));
  public isAdmin$ = this.currentUser$.pipe(map((user) => user?.role === 'admin'));

  constructor(
    private http: HttpClient,
    private router: Router
  ) {
    this.loadStoredUser();
  }

  private loadStoredUser(): void {
    const token = localStorage.getItem('accessToken');
    if (token) {
      this.getCurrentUser().subscribe({
        error: () => this.clearTokens(),
      });
    }
  }

  get currentUser(): User | null {
    return this.currentUserSubject.value;
  }

  get accessToken(): string | null {
    return localStorage.getItem('accessToken');
  }

  get refreshToken(): string | null {
    return localStorage.getItem('refreshToken');
  }

  login(credentials: LoginCredentials): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.apiUrl}/login`, credentials).pipe(
      tap((response) => this.handleAuthResponse(response)),
      catchError((error) => {
        return throwError(() => error);
      })
    );
  }

  register(data: RegisterData): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.apiUrl}/register`, data).pipe(
      tap((response) => this.handleAuthResponse(response)),
      catchError((error) => {
        return throwError(() => error);
      })
    );
  }

  logout(): Observable<void> {
    return this.http.post<void>(`${this.apiUrl}/logout`, {}).pipe(
      tap(() => {
        this.clearTokens();
        this.currentUserSubject.next(null);
        this.router.navigate(['/login']);
      }),
      catchError((error) => {
        this.clearTokens();
        this.currentUserSubject.next(null);
        this.router.navigate(['/login']);
        return throwError(() => error);
      })
    );
  }

  refreshAccessToken(): Observable<AuthResponse> {
    if (this.isRefreshing) {
      return new Observable((observer) => {
        this.refreshTokenSubject.subscribe((token) => {
          if (token) {
            observer.next({ accessToken: token } as AuthResponse);
            observer.complete();
          }
        });
      });
    }

    this.isRefreshing = true;
    this.refreshTokenSubject.next(null);

    return this.http
      .post<AuthResponse>(`${this.apiUrl}/refresh`, {
        refreshToken: this.refreshToken,
      })
      .pipe(
        tap((response) => {
          this.isRefreshing = false;
          this.storeTokens(response.accessToken, response.refreshToken);
          this.refreshTokenSubject.next(response.accessToken);
        }),
        catchError((error) => {
          this.isRefreshing = false;
          this.clearTokens();
          this.currentUserSubject.next(null);
          this.router.navigate(['/login']);
          return throwError(() => error);
        })
      );
  }

  getCurrentUser(): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/me`).pipe(
      tap((user) => this.currentUserSubject.next(user)),
      catchError((error) => {
        this.currentUserSubject.next(null);
        return throwError(() => error);
      })
    );
  }

  private handleAuthResponse(response: AuthResponse): void {
    this.storeTokens(response.accessToken, response.refreshToken);
    this.currentUserSubject.next(response.user);
  }

  private storeTokens(accessToken: string, refreshToken: string): void {
    localStorage.setItem('accessToken', accessToken);
    localStorage.setItem('refreshToken', refreshToken);
  }

  private clearTokens(): void {
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
  }
}
