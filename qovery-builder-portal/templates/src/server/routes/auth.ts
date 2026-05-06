import { Router } from 'express';
import passport from 'passport';
import { Strategy as GoogleStrategy } from 'passport-google-oauth20';
import { Strategy as OidcStrategy } from 'passport-openidconnect';
import session from 'express-session';

const router = Router();

// Determine which SSO strategy to use based on environment variables
const SSO_PROVIDER = process.env.SSO_PROVIDER || 'google';

// Session configuration
export const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'change-me-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
  },
});

// Passport serialization
passport.serializeUser((user: any, done) => done(null, user));
passport.deserializeUser((user: any, done) => done(null, user));

// Configure SSO strategy based on provider
const callbackURL = `${process.env.PORTAL_URL || 'http://localhost:3000'}/auth/callback`;

if (SSO_PROVIDER === 'google') {
  passport.use(new GoogleStrategy({
    clientID: process.env.SSO_CLIENT_ID!,
    clientSecret: process.env.SSO_CLIENT_SECRET!,
    callbackURL,
    scope: ['profile', 'email'],
  }, (_accessToken, _refreshToken, profile, done) => {
    done(null, {
      email: profile.emails?.[0]?.value || '',
      name: profile.displayName || '',
      avatarUrl: profile.photos?.[0]?.value || '',
    });
  }));
} else {
  // Generic OIDC (works for Okta, Azure AD, any OIDC provider)
  passport.use(new OidcStrategy({
    issuer: process.env.SSO_ISSUER_URL!,
    clientID: process.env.SSO_CLIENT_ID!,
    clientSecret: process.env.SSO_CLIENT_SECRET!,
    callbackURL,
    authorizationURL: `${process.env.SSO_ISSUER_URL}/authorize`,
    tokenURL: `${process.env.SSO_ISSUER_URL}/oauth/token`,
    userInfoURL: `${process.env.SSO_ISSUER_URL}/userinfo`,
    scope: 'openid profile email',
  }, (_issuer: string, profile: any, done: any) => {
    done(null, {
      email: profile.emails?.[0]?.value || profile._json?.email || '',
      name: profile.displayName || profile._json?.name || '',
      avatarUrl: profile._json?.picture || '',
    });
  }));
}

// Auth routes
router.get('/login', (req, res, next) => {
  const strategy = SSO_PROVIDER === 'google' ? 'google' : 'openidconnect';
  passport.authenticate(strategy, {
    scope: SSO_PROVIDER === 'google' ? ['profile', 'email'] : ['openid', 'profile', 'email'],
  })(req, res, next);
});

router.get('/callback',
  (req, res, next) => {
    const strategy = SSO_PROVIDER === 'google' ? 'google' : 'openidconnect';
    passport.authenticate(strategy, { failureRedirect: '/login' })(req, res, next);
  },
  (_req, res) => {
    res.redirect('/');
  }
);

router.get('/logout', (req, res) => {
  req.logout(() => {
    res.redirect('/login');
  });
});

export default router;
