// User Profile Component
import React, { useState } from 'react';
import { User, UpdateUserDTO } from '../types/user';
import { useAuth } from '../hooks/useAuth';
import { userService } from '../services/userService';

interface UserProfileProps {
  userId?: string;
  onUpdate?: (user: User) => void;
}

// Q: How does this component handle authentication state?
export function UserProfile({ userId, onUpdate }: UserProfileProps) {
  const { user: currentUser, isAuthenticated, hasRole } = useAuth();
  const [isEditing, setIsEditing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  const targetUser = userId ? null : currentUser; // Would fetch if userId provided
  const canEdit = isAuthenticated && (
    !userId ||
    userId === currentUser?.id ||
    hasRole('admin')
  );

  const handleSubmit = async (data: UpdateUserDTO) => {
    if (!targetUser) return;

    setIsLoading(true);
    setError(null);

    try {
      const updated = await userService.updateUser(targetUser.id, data);
      onUpdate?.(updated);
      setIsEditing(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Update failed');
    } finally {
      setIsLoading(false);
    }
  };

  if (!targetUser) {
    return <div>Loading user...</div>;
  }

  return (
    <div className="user-profile">
      <header className="user-profile__header">
        <h2>{targetUser.name}</h2>
        <span className="user-profile__role">{targetUser.role}</span>
      </header>

      <div className="user-profile__info">
        <p>Email: {targetUser.email}</p>
        <p>Member since: {targetUser.createdAt.toLocaleDateString()}</p>
      </div>

      {error && <div className="user-profile__error">{error}</div>}

      {canEdit && !isEditing && (
        <button onClick={() => setIsEditing(true)}>Edit Profile</button>
      )}

      {isEditing && (
        <form onSubmit={(e) => {
          e.preventDefault();
          const formData = new FormData(e.currentTarget);
          handleSubmit({
            name: formData.get('name') as string,
            email: formData.get('email') as string,
          });
        }}>
          <input name="name" defaultValue={targetUser.name} />
          <input name="email" defaultValue={targetUser.email} />
          <button type="submit" disabled={isLoading}>
            {isLoading ? 'Saving...' : 'Save'}
          </button>
          <button type="button" onClick={() => setIsEditing(false)}>
            Cancel
          </button>
        </form>
      )}
    </div>
  );
}
