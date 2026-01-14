// src/js/components/UserList.js - User list component

import { userService } from '../services/user.js';
import { authService } from '../services/auth.js';
import { EventEmitter } from '../utils/events.js';

export class UserList extends EventEmitter {
  constructor(containerSelector) {
    super();
    this.container = document.querySelector(containerSelector);
    this.users = [];
    this.total = 0;
    this.page = 1;
    this.pageSize = 20;
    this.isLoading = false;
    this.filters = {};

    this.init();
  }

  init() {
    this.render();
    this.attachEventListeners();
    this.loadUsers();
  }

  // Q: How should we implement virtual scrolling for large user lists?
  async loadUsers() {
    if (this.isLoading) return;

    this.isLoading = true;
    this.renderLoading();

    try {
      const result = await userService.getUsers({
        page: this.page,
        page_size: this.pageSize,
        ...this.filters,
      });

      this.users = result.users;
      this.total = result.total;
      this.totalPages = result.totalPages;

      this.renderUsers();
      this.renderPagination();
      this.emit('loaded', { users: this.users, total: this.total });
    } catch (error) {
      this.renderError(error);
      this.emit('error', error);
    } finally {
      this.isLoading = false;
    }
  }

  render() {
    this.container.innerHTML = `
      <div class="user-list">
        <div class="user-list__header">
          <h2>Users</h2>
          <div class="user-list__actions">
            <input type="search" class="user-list__search" placeholder="Search users...">
            <select class="user-list__filter-role">
              <option value="">All roles</option>
              <option value="admin">Admin</option>
              <option value="moderator">Moderator</option>
              <option value="user">User</option>
            </select>
            <select class="user-list__filter-status">
              <option value="">All statuses</option>
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
              <option value="suspended">Suspended</option>
              <option value="pending">Pending</option>
            </select>
          </div>
        </div>
        <div class="user-list__content"></div>
        <div class="user-list__pagination"></div>
      </div>
    `;
  }

  renderLoading() {
    const content = this.container.querySelector('.user-list__content');
    content.innerHTML = '<div class="loading">Loading...</div>';
  }

  renderUsers() {
    const content = this.container.querySelector('.user-list__content');

    if (this.users.length === 0) {
      content.innerHTML = '<div class="empty">No users found</div>';
      return;
    }

    content.innerHTML = `
      <table class="user-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Email</th>
            <th>Role</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          ${this.users.map((user) => this.renderUserRow(user)).join('')}
        </tbody>
      </table>
    `;
  }

  renderUserRow(user) {
    const isAdmin = authService.isAdmin();
    return `
      <tr data-user-id="${user.id}">
        <td>${this.escapeHtml(user.full_name || user.username)}</td>
        <td>${this.escapeHtml(user.email)}</td>
        <td><span class="badge badge--${user.role}">${user.role}</span></td>
        <td><span class="badge badge--${user.status}">${user.status}</span></td>
        <td>
          <button class="btn btn--sm btn-view" data-action="view">View</button>
          ${isAdmin ? `
            <button class="btn btn--sm btn-edit" data-action="edit">Edit</button>
            <button class="btn btn--sm btn-delete" data-action="delete">Delete</button>
          ` : ''}
        </td>
      </tr>
    `;
  }

  renderPagination() {
    const pagination = this.container.querySelector('.user-list__pagination');

    if (this.totalPages <= 1) {
      pagination.innerHTML = '';
      return;
    }

    const pages = [];
    for (let i = 1; i <= this.totalPages; i++) {
      if (
        i === 1 ||
        i === this.totalPages ||
        (i >= this.page - 2 && i <= this.page + 2)
      ) {
        pages.push(i);
      } else if (pages[pages.length - 1] !== '...') {
        pages.push('...');
      }
    }

    pagination.innerHTML = `
      <div class="pagination">
        <button class="pagination__btn" data-page="${this.page - 1}" ${this.page === 1 ? 'disabled' : ''}>
          Previous
        </button>
        ${pages
          .map((p) =>
            p === '...'
              ? '<span class="pagination__ellipsis">...</span>'
              : `<button class="pagination__btn ${p === this.page ? 'active' : ''}" data-page="${p}">${p}</button>`
          )
          .join('')}
        <button class="pagination__btn" data-page="${this.page + 1}" ${this.page === this.totalPages ? 'disabled' : ''}>
          Next
        </button>
      </div>
    `;
  }

  renderError(error) {
    const content = this.container.querySelector('.user-list__content');
    content.innerHTML = `
      <div class="error">
        <p>Failed to load users: ${this.escapeHtml(error.message)}</p>
        <button class="btn btn-retry">Retry</button>
      </div>
    `;
  }

  attachEventListeners() {
    // Search
    const searchInput = this.container.querySelector('.user-list__search');
    let searchTimeout;
    searchInput?.addEventListener('input', (e) => {
      clearTimeout(searchTimeout);
      searchTimeout = setTimeout(() => {
        this.filters.search = e.target.value;
        this.page = 1;
        this.loadUsers();
      }, 300);
    });

    // Role filter
    const roleFilter = this.container.querySelector('.user-list__filter-role');
    roleFilter?.addEventListener('change', (e) => {
      this.filters.role = e.target.value || undefined;
      this.page = 1;
      this.loadUsers();
    });

    // Status filter
    const statusFilter = this.container.querySelector('.user-list__filter-status');
    statusFilter?.addEventListener('change', (e) => {
      this.filters.status = e.target.value || undefined;
      this.page = 1;
      this.loadUsers();
    });

    // Pagination
    this.container.addEventListener('click', (e) => {
      const pageBtn = e.target.closest('[data-page]');
      if (pageBtn && !pageBtn.disabled) {
        this.page = parseInt(pageBtn.dataset.page, 10);
        this.loadUsers();
      }
    });

    // User actions
    this.container.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-action]');
      if (btn) {
        const row = btn.closest('[data-user-id]');
        const userId = row?.dataset.userId;
        const action = btn.dataset.action;

        if (userId && action) {
          this.emit(action, userId);
        }
      }
    });

    // Retry
    this.container.addEventListener('click', (e) => {
      if (e.target.closest('.btn-retry')) {
        this.loadUsers();
      }
    });
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  setFilter(key, value) {
    this.filters[key] = value;
    this.page = 1;
    this.loadUsers();
  }

  clearFilters() {
    this.filters = {};
    this.page = 1;
    this.loadUsers();
  }

  refresh() {
    this.loadUsers();
  }
}
