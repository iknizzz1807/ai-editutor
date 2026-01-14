// src/app/guards/auth.guard.ts - Route guards for authentication

import { Injectable } from '@angular/core';
import {
  CanActivate,
  CanActivateChild,
  CanLoad,
  Route,
  UrlSegment,
  ActivatedRouteSnapshot,
  RouterStateSnapshot,
  Router,
  UrlTree,
} from '@angular/router';
import { Observable, map, take } from 'rxjs';
import { AuthService } from '../services/auth.service';

// Q: How should we implement role-based route guards with lazy-loaded modules in Angular?
@Injectable({
  providedIn: 'root',
})
export class AuthGuard implements CanActivate, CanActivateChild, CanLoad {
  constructor(
    private authService: AuthService,
    private router: Router
  ) {}

  canActivate(
    route: ActivatedRouteSnapshot,
    state: RouterStateSnapshot
  ): Observable<boolean | UrlTree> {
    return this.checkAuth(route, state.url);
  }

  canActivateChild(
    childRoute: ActivatedRouteSnapshot,
    state: RouterStateSnapshot
  ): Observable<boolean | UrlTree> {
    return this.checkAuth(childRoute, state.url);
  }

  canLoad(route: Route, segments: UrlSegment[]): Observable<boolean | UrlTree> {
    const url = segments.map((s) => s.path).join('/');
    return this.checkAuth(route, url);
  }

  private checkAuth(
    route: ActivatedRouteSnapshot | Route,
    url: string
  ): Observable<boolean | UrlTree> {
    return this.authService.currentUser$.pipe(
      take(1),
      map((user) => {
        if (!user) {
          // Store intended destination for redirect after login
          sessionStorage.setItem('redirectUrl', url);
          return this.router.createUrlTree(['/login']);
        }

        // Check required roles
        const requiredRoles = route.data?.['roles'] as string[] | undefined;
        if (requiredRoles && requiredRoles.length > 0) {
          if (!requiredRoles.includes(user.role)) {
            return this.router.createUrlTree(['/unauthorized']);
          }
        }

        // Check if email verification is required
        const requireVerified = route.data?.['requireVerified'] as boolean | undefined;
        if (requireVerified && !user.emailVerified) {
          return this.router.createUrlTree(['/verify-email']);
        }

        return true;
      })
    );
  }
}

@Injectable({
  providedIn: 'root',
})
export class GuestGuard implements CanActivate {
  constructor(
    private authService: AuthService,
    private router: Router
  ) {}

  canActivate(): Observable<boolean | UrlTree> {
    return this.authService.currentUser$.pipe(
      take(1),
      map((user) => {
        if (user) {
          // Redirect to stored URL or home
          const redirectUrl = sessionStorage.getItem('redirectUrl') || '/';
          sessionStorage.removeItem('redirectUrl');
          return this.router.createUrlTree([redirectUrl]);
        }
        return true;
      })
    );
  }
}

@Injectable({
  providedIn: 'root',
})
export class AdminGuard implements CanActivate {
  constructor(
    private authService: AuthService,
    private router: Router
  ) {}

  canActivate(): Observable<boolean | UrlTree> {
    return this.authService.isAdmin$.pipe(
      take(1),
      map((isAdmin) => {
        if (!isAdmin) {
          return this.router.createUrlTree(['/unauthorized']);
        }
        return true;
      })
    );
  }
}
