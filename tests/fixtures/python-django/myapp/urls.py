# myapp/urls.py - URL configuration

from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views.user import UserViewSet, UserAddressViewSet

router = DefaultRouter()
router.register(r'users', UserViewSet, basename='user')
router.register(r'addresses', UserAddressViewSet, basename='address')

urlpatterns = [
    path('api/v1/', include(router.urls)),
]
