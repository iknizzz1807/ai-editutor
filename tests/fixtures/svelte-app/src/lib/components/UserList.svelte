<script lang="ts">
  // src/lib/components/UserList.svelte - User list component

  import { onMount } from 'svelte';
  import {
    usersStore,
    users,
    totalUsers,
    currentPage,
    totalPages,
    usersLoading,
    usersError,
    selectedUserIds,
    hasSelection,
  } from '$lib/stores/users';
  import { isAdmin } from '$lib/stores/auth';
  import type { User, UserFilters } from '$lib/types';

  export let initialFilters: UserFilters = {};

  let searchInput = '';
  let roleFilter = '';
  let statusFilter = '';

  // Q: How should we implement keyboard navigation and selection in Svelte data tables?
  $: pageNumbers = generatePageNumbers($currentPage, $totalPages);

  function generatePageNumbers(current: number, total: number): (number | string)[] {
    const pages: (number | string)[] = [];
    for (let i = 1; i <= total; i++) {
      if (i === 1 || i === total || (i >= current - 2 && i <= current + 2)) {
        pages.push(i);
      } else if (pages[pages.length - 1] !== '...') {
        pages.push('...');
      }
    }
    return pages;
  }

  function handleSearch() {
    usersStore.setFilter('search', searchInput || undefined);
  }

  function handleRoleFilter() {
    usersStore.setFilter('role', roleFilter || undefined);
  }

  function handleStatusFilter() {
    usersStore.setFilter('status', statusFilter || undefined);
  }

  function handleClearFilters() {
    searchInput = '';
    roleFilter = '';
    statusFilter = '';
    usersStore.clearFilters();
  }

  async function handleDelete(user: User) {
    if (confirm(`Are you sure you want to delete ${user.username}?`)) {
      try {
        await usersStore.deleteUser(user.id);
      } catch {
        // Error handled by store
      }
    }
  }

  async function handleBulkDelete() {
    if (confirm('Are you sure you want to delete selected users?')) {
      try {
        await usersStore.bulkDelete();
      } catch {
        // Error handled by store
      }
    }
  }

  onMount(() => {
    if (Object.keys(initialFilters).length > 0) {
      Object.entries(initialFilters).forEach(([key, value]) => {
        usersStore.setFilter(key as keyof UserFilters, value);
      });
    } else {
      usersStore.fetchUsers();
    }
  });
</script>

<div class="user-list">
  <div class="user-list__header">
    <h2>Users ({$totalUsers})</h2>

    <div class="user-list__filters">
      <input
        type="search"
        placeholder="Search users..."
        bind:value={searchInput}
        on:input={handleSearch}
        class="user-list__search"
      />

      <select bind:value={roleFilter} on:change={handleRoleFilter} class="user-list__filter">
        <option value="">All roles</option>
        <option value="admin">Admin</option>
        <option value="moderator">Moderator</option>
        <option value="user">User</option>
        <option value="guest">Guest</option>
      </select>

      <select bind:value={statusFilter} on:change={handleStatusFilter} class="user-list__filter">
        <option value="">All statuses</option>
        <option value="active">Active</option>
        <option value="inactive">Inactive</option>
        <option value="suspended">Suspended</option>
        <option value="pending">Pending</option>
      </select>

      <button on:click={handleClearFilters} class="btn btn--secondary">
        Clear Filters
      </button>
    </div>
  </div>

  {#if $hasSelection && $isAdmin}
    <div class="user-list__bulk-actions">
      <span>{$selectedUserIds.size} selected</span>
      <button on:click={handleBulkDelete} class="btn btn--danger">
        Delete Selected
      </button>
    </div>
  {/if}

  {#if $usersError}
    <div class="user-list__error">
      {$usersError}
      <button on:click={() => usersStore.fetchUsers()}>Retry</button>
    </div>
  {/if}

  {#if $usersLoading}
    <div class="user-list__loading">Loading...</div>
  {:else if $users.length > 0}
    <table class="user-table">
      <thead>
        <tr>
          {#if $isAdmin}
            <th>
              <input
                type="checkbox"
                checked={$selectedUserIds.size === $users.length}
                on:change={() =>
                  $selectedUserIds.size === $users.length
                    ? usersStore.clearSelection()
                    : usersStore.selectAll()
                }
              />
            </th>
          {/if}
          <th>Name</th>
          <th>Email</th>
          <th>Role</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        {#each $users as user (user.id)}
          <tr>
            {#if $isAdmin}
              <td>
                <input
                  type="checkbox"
                  checked={$selectedUserIds.has(user.id)}
                  on:change={() => usersStore.toggleSelection(user.id)}
                />
              </td>
            {/if}
            <td>{user.fullName || user.username}</td>
            <td>{user.email}</td>
            <td>
              <span class="badge badge--{user.role}">{user.role}</span>
            </td>
            <td>
              <span class="badge badge--{user.status}">{user.status}</span>
            </td>
            <td>
              <a href="/users/{user.id}" class="btn btn--sm">View</a>
              {#if $isAdmin}
                <a href="/users/{user.id}/edit" class="btn btn--sm">Edit</a>
                <button on:click={() => handleDelete(user)} class="btn btn--sm btn--danger">
                  Delete
                </button>
              {/if}
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  {:else}
    <div class="user-list__empty">No users found</div>
  {/if}

  {#if $totalPages > 1}
    <div class="pagination">
      <button
        disabled={$currentPage === 1}
        on:click={() => usersStore.setPage($currentPage - 1)}
        class="pagination__btn"
      >
        Previous
      </button>

      {#each pageNumbers as p}
        {#if p === '...'}
          <span class="pagination__ellipsis">...</span>
        {:else}
          <button
            class="pagination__btn"
            class:active={p === $currentPage}
            on:click={() => usersStore.setPage(p as number)}
          >
            {p}
          </button>
        {/if}
      {/each}

      <button
        disabled={$currentPage === $totalPages}
        on:click={() => usersStore.setPage($currentPage + 1)}
        class="pagination__btn"
      >
        Next
      </button>
    </div>
  {/if}
</div>

<style>
  .user-list {
    padding: 1rem;
  }

  .user-list__header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }

  .user-list__filters {
    display: flex;
    gap: 0.5rem;
  }

  .user-list__bulk-actions {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 0.75rem;
    background: #f0f0f0;
    border-radius: 4px;
    margin-bottom: 1rem;
  }

  .user-table {
    width: 100%;
    border-collapse: collapse;
  }

  .user-table th,
  .user-table td {
    padding: 0.75rem;
    text-align: left;
    border-bottom: 1px solid #eee;
  }

  .pagination {
    display: flex;
    justify-content: center;
    gap: 0.25rem;
    margin-top: 1rem;
  }

  .pagination__btn {
    padding: 0.5rem 0.75rem;
  }

  .pagination__btn.active {
    background: #007bff;
    color: white;
  }
</style>
