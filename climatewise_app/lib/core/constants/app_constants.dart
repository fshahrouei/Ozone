// lib/core/constants/app_constants.dart

/// Force the app to always show the onboarding screen at startup
const bool FORCE_SHOW_ONBOARDING = false;

/// App direction / language configuration
const bool IS_RTL = false; // If true, the app layout will be Right-to-Left (e.g., Persian)
const String APP_LOCALE = IS_RTL ? 'ar' : 'en'; // 'ar' for RTL, 'en' for LTR

/// Theme configuration
const bool IS_DARK_THEME = false; // Set true to test dark theme

/// Force the app to always show login screen
const bool FORCE_SHOW_LOGIN = false; // For testing: set to true/false as needed

/// Base API URL for server requests
// const String BASE_API_URL = "https://6889c8254c55d5c7395382aa.mockapi.io/api/v1/";
const String BASE_API_URL = "https://climatewise.app/api/v1/";

/// Force checking app version from server
const bool FORCE_CHECK_VERSION = false;
