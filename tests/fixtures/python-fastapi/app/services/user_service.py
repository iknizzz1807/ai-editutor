# User service
import uuid
from typing import List, Optional
from sqlalchemy.orm import Session
from fastapi import Depends, HTTPException, status

from app.models.user import User, UserCreate, UserUpdate, UserRole
from app.services.auth_service import AuthService, get_auth_service
from app.database import get_db


class UserService:
    """User management service."""

    def __init__(self, db: Session, auth_service: AuthService):
        self.db = db
        self.auth_service = auth_service

    def get_users(
        self,
        skip: int = 0,
        limit: int = 100,
        role: Optional[UserRole] = None,
        search: Optional[str] = None,
    ) -> List[User]:
        query = self.db.query(User)

        if role:
            query = query.filter(User.role == role)

        if search:
            search_term = f"%{search}%"
            query = query.filter(
                (User.name.ilike(search_term)) |
                (User.email.ilike(search_term))
            )

        return query.offset(skip).limit(limit).all()

    def get_user_by_id(self, user_id: str) -> User:
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        return user

    def get_user_by_email(self, email: str) -> Optional[User]:
        return self.db.query(User).filter(User.email == email).first()

    def create_user(self, user_data: UserCreate) -> User:
        # Check if email already exists
        existing = self.get_user_by_email(user_data.email)
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered",
            )

        # Create new user
        user = User(
            id=str(uuid.uuid4()),
            email=user_data.email,
            name=user_data.name,
            hashed_password=self.auth_service.get_password_hash(user_data.password),
            role=user_data.role,
        )

        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user

    def update_user(self, user_id: str, user_data: UserUpdate) -> User:
        user = self.get_user_by_id(user_id)

        # Check email uniqueness if changing
        if user_data.email and user_data.email != user.email:
            existing = self.get_user_by_email(user_data.email)
            if existing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email already in use",
                )

        # Update fields
        update_data = user_data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(user, field, value)

        self.db.commit()
        self.db.refresh(user)
        return user

    def delete_user(self, user_id: str) -> None:
        user = self.get_user_by_id(user_id)
        self.db.delete(user)
        self.db.commit()


def get_user_service(
    db: Session = Depends(get_db),
    auth_service: AuthService = Depends(get_auth_service),
) -> UserService:
    return UserService(db, auth_service)
