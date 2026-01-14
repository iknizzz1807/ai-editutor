// src/js/app.js - Application entry point

import { authService } from './services/auth.js';
import { userService } from './services/user.js';
import { UserList } from './components/UserList.js';
import { eventBus, dom } from './utils/events.js';
import { config } from './config/index.js';

class App {
  constructor() {
    this.components = {};
    this.init();
  }

  init() {
    dom.ready(() => {
      this.setupAuth();
      this.setupRouting();
      this.setupComponents();
      this.setupGlobalEvents();

      console.log(`${config.appName} v${config.appVersion} initialized`);
    });
  }

  setupAuth() {
    // Listen for auth state changes
    authService.on('authChange', ({ isAuthenticated, user }) => {
      this.updateUI(isAuthenticated, user);
    });

    authService.on('logout', () => {
      this.navigate('/login');
    });
  }

  setupRouting() {
    // Simple hash-based routing
    window.addEventListener('hashchange', () => this.handleRoute());
    this.handleRoute();
  }

  handleRoute() {
    const hash = window.location.hash.slice(1) || '/';
    const routes = {
      '/': this.showHome.bind(this),
      '/login': this.showLogin.bind(this),
      '/register': this.showRegister.bind(this),
      '/users': this.showUsers.bind(this),
      '/profile': this.showProfile.bind(this),
    };

    const handler = routes[hash];
    if (handler) {
      handler();
    } else {
      this.show404();
    }
  }

  navigate(path) {
    window.location.hash = path;
  }

  setupComponents() {
    // Initialize components when their containers exist
    const userListContainer = document.querySelector('#user-list');
    if (userListContainer) {
      this.components.userList = new UserList('#user-list');

      this.components.userList.on('view', (userId) => {
        this.navigate(`/users/${userId}`);
      });

      this.components.userList.on('edit', (userId) => {
        this.showEditUserModal(userId);
      });

      this.components.userList.on('delete', (userId) => {
        this.confirmDeleteUser(userId);
      });
    }
  }

  setupGlobalEvents() {
    // Handle global click events
    document.addEventListener('click', (e) => {
      // Logout button
      if (e.target.closest('[data-action="logout"]')) {
        e.preventDefault();
        authService.logout();
      }

      // Navigation links
      const navLink = e.target.closest('[data-navigate]');
      if (navLink) {
        e.preventDefault();
        this.navigate(navLink.dataset.navigate);
      }
    });

    // Handle form submissions
    document.addEventListener('submit', (e) => {
      const form = e.target;

      if (form.id === 'login-form') {
        e.preventDefault();
        this.handleLogin(form);
      }

      if (form.id === 'register-form') {
        e.preventDefault();
        this.handleRegister(form);
      }
    });

    // Listen for service events
    userService.on('userDeleted', () => {
      this.components.userList?.refresh();
    });
  }

  updateUI(isAuthenticated, user) {
    const authElements = document.querySelectorAll('[data-auth]');
    authElements.forEach((el) => {
      const showWhen = el.dataset.auth;
      if (showWhen === 'authenticated') {
        el.style.display = isAuthenticated ? '' : 'none';
      } else if (showWhen === 'guest') {
        el.style.display = isAuthenticated ? 'none' : '';
      }
    });

    // Update user info
    const userNameElements = document.querySelectorAll('[data-user="name"]');
    userNameElements.forEach((el) => {
      el.textContent = user?.full_name || user?.username || '';
    });

    const userEmailElements = document.querySelectorAll('[data-user="email"]');
    userEmailElements.forEach((el) => {
      el.textContent = user?.email || '';
    });
  }

  async handleLogin(form) {
    const formData = new FormData(form);
    const email = formData.get('email');
    const password = formData.get('password');

    try {
      await authService.login(email, password);
      this.navigate('/');
    } catch (error) {
      this.showError(form, error.message);
    }
  }

  async handleRegister(form) {
    const formData = new FormData(form);
    const userData = {
      email: formData.get('email'),
      username: formData.get('username'),
      password: formData.get('password'),
    };

    try {
      await authService.register(userData);
      this.navigate('/');
    } catch (error) {
      this.showError(form, error.message);
    }
  }

  async confirmDeleteUser(userId) {
    if (confirm('Are you sure you want to delete this user?')) {
      try {
        await userService.deleteUser(userId);
        this.showNotification('User deleted successfully');
      } catch (error) {
        this.showNotification(error.message, 'error');
      }
    }
  }

  showError(form, message) {
    const errorEl = form.querySelector('.form-error') || document.createElement('div');
    errorEl.className = 'form-error';
    errorEl.textContent = message;
    if (!form.querySelector('.form-error')) {
      form.prepend(errorEl);
    }
  }

  showNotification(message, type = 'success') {
    eventBus.emit('notification', { message, type });
  }

  showHome() {
    this.setActiveView('home');
  }

  showLogin() {
    if (authService.getIsAuthenticated()) {
      this.navigate('/');
      return;
    }
    this.setActiveView('login');
  }

  showRegister() {
    if (authService.getIsAuthenticated()) {
      this.navigate('/');
      return;
    }
    this.setActiveView('register');
  }

  showUsers() {
    if (!authService.getIsAuthenticated()) {
      this.navigate('/login');
      return;
    }
    this.setActiveView('users');
    this.components.userList?.refresh();
  }

  showProfile() {
    if (!authService.getIsAuthenticated()) {
      this.navigate('/login');
      return;
    }
    this.setActiveView('profile');
  }

  show404() {
    this.setActiveView('404');
  }

  setActiveView(viewName) {
    document.querySelectorAll('[data-view]').forEach((el) => {
      el.style.display = el.dataset.view === viewName ? '' : 'none';
    });
  }

  showEditUserModal(userId) {
    // Would implement modal
    console.log('Edit user:', userId);
  }
}

// Initialize app
const app = new App();
export default app;
