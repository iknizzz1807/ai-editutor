# User router
from typing import List, Optional
from fastapi import APIRouter, Depends, Query

from app.models.user import User, UserCreate, UserUpdate, UserResponse, UserRole
from app.services.user_service import UserService, get_user_service
from app.services.auth_service import AuthService, get_auth_service, oauth2_scheme

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/", response_model=List[UserResponse])
async def list_users(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    role: Optional[UserRole] = None,
    search: Optional[str] = None,
    user_service: UserService = Depends(get_user_service),
    token: str = Depends(oauth2_scheme),
    auth_service: AuthService = Depends(get_auth_service),
):
    """List all users with optional filtering."""
    # Verify authentication
    auth_service.get_current_user(token)
    return user_service.get_users(skip=skip, limit=limit, role=role, search=search)


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    user_service: UserService = Depends(get_user_service),
    token: str = Depends(oauth2_scheme),
    auth_service: AuthService = Depends(get_auth_service),
):
    """Get a specific user by ID."""
    auth_service.get_current_user(token)
    return user_service.get_user_by_id(user_id)


# Q: What validation happens when creating a user?
@router.post("/", response_model=UserResponse, status_code=201)
async def create_user(
    user_data: UserCreate,
    user_service: UserService = Depends(get_user_service),
    token: str = Depends(oauth2_scheme),
    auth_service: AuthService = Depends(get_auth_service),
):
    """Create a new user. Requires admin role."""
    current_user = auth_service.get_current_user(token)
    auth_service.require_role(UserRole.ADMIN)(current_user)
    return user_service.create_user(user_data)


@router.put("/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: str,
    user_data: UserUpdate,
    user_service: UserService = Depends(get_user_service),
    token: str = Depends(oauth2_scheme),
    auth_service: AuthService = Depends(get_auth_service),
):
    """Update a user. Users can update themselves, admins can update anyone."""
    current_user = auth_service.get_current_user(token)

    # Allow self-update or admin update
    if current_user.id != user_id and current_user.role != UserRole.ADMIN:
        auth_service.require_role(UserRole.ADMIN)(current_user)

    return user_service.update_user(user_id, user_data)


@router.delete("/{user_id}", status_code=204)
async def delete_user(
    user_id: str,
    user_service: UserService = Depends(get_user_service),
    token: str = Depends(oauth2_scheme),
    auth_service: AuthService = Depends(get_auth_service),
):
    """Delete a user. Requires admin role."""
    current_user = auth_service.get_current_user(token)
    auth_service.require_role(UserRole.ADMIN)(current_user)
    user_service.delete_user(user_id)
