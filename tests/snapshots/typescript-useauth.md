# Snapshot: TypeScript useAuth Hook

This document shows what gets sent to the LLM when a user asks a question in a TypeScript React hook.

## Input

### Source File
- **Path:** `tests/fixtures/typescript-fullstack/src/hooks/useAuth.ts`
- **Filetype:** `typescript`
- **Total lines:** 179

### Question Location
- **Line number:** 108
- **Q: Comment:** `// Q: How does the logout function handle cleanup of subscriptions and pending requests?`

### Related Files (same project)
```
src/
├── hooks/
│   └── useAuth.ts          <- THIS FILE
├── services/
│   └── authService.ts      <- imported
├── utils/
│   └── storage.ts          <- imported
└── types/
    ├── user.ts             <- imported
    └── auth.ts             <- imported
```

## Context Extraction

### Imports Detected
```typescript
import { useState, useEffect, useCallback, useMemo } from 'react';
import authService from '../services/authService';
import { saveAuthTokens, clearAuthTokens, hasValidTokens } from '../utils/storage';
import {
  User,
  UserRole,
} from '../types/user';
import {
  LoginCredentials,
  RegisterData,
  AuthState,
  ChangePasswordRequest,
} from '../types/auth';
```

### Code Context (±50 lines around question)
The `>>>` marker shows where the question line is located:

```typescript
     66:   const login = useCallback(async (credentials: LoginCredentials) => {
     67:     setState((prev) => ({ ...prev, isLoading: true, error: null }));
     68:     try {
     69:       const response = await authService.login(credentials);
     70:       setState({
     71:         user: response.user,
     72:         tokens: response.tokens,
     73:         isAuthenticated: true,
     74:         isLoading: false,
     75:         error: null,
     76:       });
     77:     } catch (error: any) {
     78:       setState((prev) => ({
     79:         ...prev,
     80:         isLoading: false,
     81:         error: error.message || 'Login failed',
     82:       }));
     83:       throw error;
     84:     }
     85:   }, []);
     86:
     87:   const register = useCallback(async (data: RegisterData) => {
     88:     setState((prev) => ({ ...prev, isLoading: true, error: null }));
     89:     try {
     90:       const response = await authService.register(data);
     91:       setState({
     92:         user: response.user,
     93:         tokens: response.tokens,
     94:         isAuthenticated: true,
     95:         isLoading: false,
     96:         error: null,
     97:       });
     98:     } catch (error: any) {
     99:       setState((prev) => ({
    100:         ...prev,
    101:         isLoading: false,
    102:         error: error.message || 'Registration failed',
    103:       }));
    104:       throw error;
    105:     }
    106:   }, []);
    107:
>>> 108:   // Q: How does the logout function handle cleanup of subscriptions and pending requests?
    109:   const logout = useCallback(async () => {
    110:     setState((prev) => ({ ...prev, isLoading: true }));
    111:     try {
    112:       await authService.logout();
    113:     } finally {
    114:       setState({
    115:         user: null,
    116:         tokens: null,
    117:         isAuthenticated: false,
    118:         isLoading: false,
    119:         error: null,
    120:       });
    121:     }
    122:   }, []);
    123:
    124:   const changePassword = useCallback(async (data: ChangePasswordRequest) => {
    125:     setState((prev) => ({ ...prev, isLoading: true, error: null }));
    ...
```

## LLM Payload

### System Prompt

```
You are an expert coding mentor helping a developer learn and understand code.

Your role is to TEACH, not to do the work for them.

CRITICAL: Your response will be inserted as an INLINE COMMENT directly in the code file.
Keep responses CONCISE and well-structured. Avoid excessive length.

CORE PRINCIPLES:
1. EXPLAIN concepts clearly, don't just give solutions
2. Reference the actual code context provided
3. Always respond in English
4. Be concise - this will appear as code comments
5. Use plain text, avoid emoji headers

RESPONSE GUIDELINES:
- Keep explanations focused and to the point
- Include 1-2 short code examples when helpful
- Mention best practices briefly
- Warn about common mistakes in 1-2 sentences
- Suggest what to learn next in one line

DO NOT:
- Use emoji headers (no 📚, 💡, ✅, etc.)
- Write overly long responses
- Repeat information unnecessarily

QUESTION mode - Give direct, educational answer.

Structure:
1. Direct answer first (clear and concise)
2. Brief explanation of why/how
3. One code example if helpful
4. One common mistake to avoid
5. One thing to learn next
```

### User Prompt

```
Mode: Q

Context:
Language: typescript
File: useAuth.ts

Imports:
​```typescript
import { useState, useEffect, useCallback, useMemo } from 'react';
import authService from '../services/authService';
import { saveAuthTokens, clearAuthTokens, hasValidTokens } from '../utils/storage';
...
​```

Code context (>>> marks the question line):
​```typescript
     66:   const login = useCallback(async (credentials: LoginCredentials) => {
     ...
>>> 108:   // Q: How does the logout function handle cleanup of subscriptions and pending requests?
    109:   const logout = useCallback(async () => {
    110:     setState((prev) => ({ ...prev, isLoading: true }));
    111:     try {
    112:       await authService.logout();
    113:     } finally {
    ...
​```

Question:
How does the logout function handle cleanup of subscriptions and pending requests?
```

## Expected Response Location

The AI response will be inserted as a block comment directly after line 108:

```typescript
  // Q: How does the logout function handle cleanup of subscriptions and pending requests?

  /*
  A:
  Currently, the logout function does NOT handle cleanup of subscriptions or pending requests.
  It only:
  1. Sets loading state
  2. Calls authService.logout()
  3. Resets state in finally block

  To properly handle cleanup, you should:
  - Use AbortController for pending fetch requests
  - Store subscription references and call unsubscribe() on logout

  Example pattern:
  const abortController = useRef<AbortController>();
  // In logout:
  abortController.current?.abort();

  Common mistake: Forgetting cleanup can cause memory leaks and "setState on unmounted component" warnings.

  Learn next: React cleanup patterns with useEffect return function.
  */
  const logout = useCallback(async () => {
```
