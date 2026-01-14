// src/app/components/user-list/user-list.component.ts - User list component

import { Component, OnInit, OnDestroy, Input } from '@angular/core';
import { Subject, takeUntil, combineLatest } from 'rxjs';
import { UserService } from '../../services/user.service';
import { AuthService } from '../../services/auth.service';
import { User, UserFilters } from '../../models/user.model';

// Q: How should we implement virtual scrolling with Angular CDK for large datasets with dynamic row heights?
@Component({
  selector: 'app-user-list',
  templateUrl: './user-list.component.html',
  styleUrls: ['./user-list.component.scss'],
})
export class UserListComponent implements OnInit, OnDestroy {
  @Input() initialFilters: UserFilters = {};

  users$ = this.userService.users$;
  total$ = this.userService.total$;
  page$ = this.userService.page$;
  totalPages$ = this.userService.totalPages$;
  isLoading$ = this.userService.isLoading$;
  error$ = this.userService.error$;
  isAdmin$ = this.authService.isAdmin$;

  searchInput = '';
  roleFilter = '';
  statusFilter = '';
  selectedIds = new Set<string>();

  private destroy$ = new Subject<void>();

  constructor(
    private userService: UserService,
    private authService: AuthService
  ) {}

  ngOnInit(): void {
    if (Object.keys(this.initialFilters).length > 0) {
      Object.entries(this.initialFilters).forEach(([key, value]) => {
        this.userService.setFilter(key as keyof UserFilters, value);
      });
    } else {
      this.userService.fetchUsers().pipe(takeUntil(this.destroy$)).subscribe();
    }
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  getPageNumbers(currentPage: number, totalPages: number): (number | string)[] {
    const pages: (number | string)[] = [];
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || (i >= currentPage - 2 && i <= currentPage + 2)) {
        pages.push(i);
      } else if (pages[pages.length - 1] !== '...') {
        pages.push('...');
      }
    }
    return pages;
  }

  handleSearch(): void {
    this.userService.setFilter('search', this.searchInput || undefined);
  }

  handleRoleFilter(): void {
    this.userService.setFilter('role', this.roleFilter || undefined);
  }

  handleStatusFilter(): void {
    this.userService.setFilter('status', this.statusFilter || undefined);
  }

  handleClearFilters(): void {
    this.searchInput = '';
    this.roleFilter = '';
    this.statusFilter = '';
    this.userService.clearFilters();
  }

  handlePageChange(page: number): void {
    this.userService.setPage(page);
  }

  toggleSelection(userId: string): void {
    if (this.selectedIds.has(userId)) {
      this.selectedIds.delete(userId);
    } else {
      this.selectedIds.add(userId);
    }
  }

  selectAll(users: User[]): void {
    if (this.selectedIds.size === users.length) {
      this.selectedIds.clear();
    } else {
      this.selectedIds = new Set(users.map((u) => u.id));
    }
  }

  handleDelete(user: User): void {
    if (confirm(`Are you sure you want to delete ${user.username}?`)) {
      this.userService
        .deleteUser(user.id)
        .pipe(takeUntil(this.destroy$))
        .subscribe();
    }
  }

  trackByUserId(index: number, user: User): string {
    return user.id;
  }
}
