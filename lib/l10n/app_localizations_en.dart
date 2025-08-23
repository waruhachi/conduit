// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Conduit';

  @override
  String get initializationFailed => 'Initialization Failed';

  @override
  String get retry => 'Retry';

  @override
  String get back => 'Back';

  @override
  String get you => 'You';

  @override
  String get loadingProfile => 'Loading profile...';

  @override
  String get unableToLoadProfile => 'Unable to load profile';

  @override
  String get pleaseCheckConnection => 'Please check your connection and try again';

  @override
  String get account => 'Account';

  @override
  String get signOut => 'Sign Out';

  @override
  String get endYourSession => 'End your session';

  @override
  String get defaultModel => 'Default Model';

  @override
  String get autoSelect => 'Auto-select';

  @override
  String get loadingModels => 'Loading models...';

  @override
  String get failedToLoadModels => 'Failed to load models';

  @override
  String get availableModels => 'Available Models';

  @override
  String get noResults => 'No results';

  @override
  String get searchModels => 'Search models...';

  @override
  String get errorMessage => 'Something went wrong. Please try again.';

  @override
  String get loginButton => 'Login';

  @override
  String get menuItem => 'Settings';

  @override
  String dynamicContentWithPlaceholder(String name) {
    return 'Welcome, $name!';
  }

  @override
  String itemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items',
    );
    return '$_temp0';
  }

  @override
  String get closeButtonSemantic => 'Close';

  @override
  String get loadingContent => 'Loading content';

  @override
  String get noItems => 'No items';

  @override
  String get noItemsToDisplay => 'No items to display';

  @override
  String get loadMore => 'Load More';

  @override
  String get workspace => 'Workspace';

  @override
  String get recentFiles => 'Recent Files';

  @override
  String get knowledgeBase => 'Knowledge Base';

  @override
  String get noFilesYet => 'No files yet';

  @override
  String get uploadDocsPrompt => 'Upload documents to reference in your conversations with Conduit';

  @override
  String get uploadFirstFile => 'Upload your first file';

  @override
  String get knowledgeBaseEmpty => 'Knowledge base is empty';

  @override
  String get createCollectionsPrompt => 'Create collections of related documents for easy reference';

  @override
  String get chooseSourcePhoto => 'Choose your source';

  @override
  String get takePhoto => 'Take a photo';

  @override
  String get chooseFromGallery => 'Choose from your photos';

  @override
  String get document => 'Document';

  @override
  String get documentHint => 'PDF, Word, or text file';

  @override
  String get uploadFileTitle => 'Upload File';

  @override
  String fileUploadComingSoon(String type) {
    return 'File upload for $type is coming soon!';
  }

  @override
  String get kbCreationComingSoon => 'Knowledge base creation is coming soon!';

  @override
  String get backToServerSetup => 'Back to server setup';

  @override
  String get connectedToServer => 'Connected to Server';

  @override
  String get signIn => 'Sign In';

  @override
  String get enterCredentials => 'Enter your credentials to access your AI conversations';

  @override
  String get credentials => 'Credentials';

  @override
  String get apiKey => 'API Key';

  @override
  String get usernameOrEmail => 'Username or Email';

  @override
  String get password => 'Password';

  @override
  String get signInWithApiKey => 'Sign in with API Key';

  @override
  String get connectToServer => 'Connect to Server';

  @override
  String get enterServerAddress => 'Enter your Open-WebUI server address to get started';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get serverUrlHint => 'https://your-server.com';

  @override
  String get enterServerUrlSemantic => 'Enter your server URL or IP address';

  @override
  String get headerName => 'Header Name';

  @override
  String get headerValue => 'Header Value';

  @override
  String get headerValueHint => 'api-key-123 or Bearer token';

  @override
  String get addHeader => 'Add header';

  @override
  String get maximumHeadersReached => 'Maximum headers reached';

  @override
  String get removeHeader => 'Remove header';

  @override
  String get connecting => 'Connecting...';

  @override
  String get connectToServerButton => 'Connect to Server';

  @override
  String get demoModeActive => 'Demo Mode Active';

  @override
  String get skipServerSetupTryDemo => 'Skip server setup and try the demo';

  @override
  String get enterDemo => 'Enter Demo';

  @override
  String get demoBadge => 'Demo';

  @override
  String get serverNotOpenWebUI => 'This does not appear to be an Open-WebUI server.';

  @override
  String get serverUrlEmpty => 'Server URL cannot be empty';

  @override
  String get invalidUrlFormat => 'Invalid URL format. Please check your input.';

  @override
  String get onlyHttpHttps => 'Only HTTP and HTTPS protocols are supported.';

  @override
  String get serverAddressRequired => 'Server address is required (e.g., 192.168.1.10 or example.com).';

  @override
  String get portRange => 'Port must be between 1 and 65535.';

  @override
  String get invalidIpFormat => 'Invalid IP address format. Use format like 192.168.1.10.';

  @override
  String get couldNotConnectGeneric => 'Couldn\'t connect. Double-check the address and try again.';

  @override
  String get weCouldntReachServer => 'We couldn\'t reach the server. Check your connection and that the server is running.';

  @override
  String get connectionTimedOut => 'Connection timed out. The server might be busy or blocked by a firewall.';

  @override
  String get useHttpOrHttpsOnly => 'Use http:// or https:// only.';

  @override
  String get loginFailed => 'Login failed';

  @override
  String get invalidCredentials => 'Invalid username or password. Please try again.';

  @override
  String get serverRedirectingHttps => 'The server is redirecting requests. Check your server\'s HTTPS configuration.';

  @override
  String get unableToConnectServer => 'Unable to connect to server. Please check your connection.';

  @override
  String get requestTimedOut => 'The request timed out. Please try again.';

  @override
  String get genericSignInFailed => 'We couldn\'t sign you in. Check your credentials and server settings.';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get done => 'Done';

  @override
  String get onboardStartTitle => 'Start a conversation';

  @override
  String get onboardStartSubtitle => 'Choose a model, then type below to begin. Tap New Chat anytime.';

  @override
  String get onboardStartBullet1 => 'Tap the model name in the top bar to switch models';

  @override
  String get onboardStartBullet2 => 'Use New Chat to reset context';

  @override
  String get onboardAttachTitle => 'Attach context';

  @override
  String get onboardAttachSubtitle => 'Ground responses by adding files or images.';

  @override
  String get onboardAttachBullet1 => 'Files: PDFs, docs, datasets';

  @override
  String get onboardAttachBullet2 => 'Images: photos or screenshots';

  @override
  String get onboardSpeakTitle => 'Speak naturally';

  @override
  String get onboardSpeakSubtitle => 'Tap the mic to dictate with live waveform feedback.';

  @override
  String get onboardSpeakBullet1 => 'Stop anytime; partial text is preserved';

  @override
  String get onboardSpeakBullet2 => 'Great for quick notes or long prompts';

  @override
  String get onboardQuickTitle => 'Quick actions';

  @override
  String get onboardQuickSubtitle => 'Use the top‑left menu to open the chats list and navigation.';

  @override
  String get onboardQuickBullet1 => 'Tap the menu to open the chats list and navigation';

  @override
  String get onboardQuickBullet2 => 'Jump instantly to New Chat, Files, or Profile';

  @override
  String get addAttachment => 'Add attachment';

  @override
  String get tools => 'Tools';

  @override
  String get voiceInput => 'Voice input';

  @override
  String get messageInputLabel => 'Message input';

  @override
  String get messageInputHint => 'Type your message';

  @override
  String get messageHintText => 'Message...';

  @override
  String get stopGenerating => 'Stop generating';

  @override
  String get send => 'Send';

  @override
  String get sendMessage => 'Send message';

  @override
  String get file => 'File';

  @override
  String get photo => 'Photo';

  @override
  String get camera => 'Camera';

  @override
  String get apiUnavailable => 'API service not available';

  @override
  String get unableToLoadImage => 'Unable to load image';

  @override
  String notAnImageFile(String fileName) {
    return 'Not an image file: $fileName';
  }

  @override
  String failedToLoadImage(String error) {
    return 'Failed to load image: $error';
  }

  @override
  String get invalidDataUrl => 'Invalid data URL format';

  @override
  String get failedToDecodeImage => 'Failed to decode image';

  @override
  String get invalidImageFormat => 'Invalid image format';

  @override
  String get emptyImageData => 'Empty image data';

  @override
  String get offlineBanner => 'You\'re offline. Some features may be limited.';

  @override
  String get featureRequiresInternet => 'This feature requires an internet connection';

  @override
  String get messagesWillSendWhenOnline => 'Messages will be sent when you\'re back online';

  @override
  String get confirm => 'Confirm';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get inputField => 'Input field';

  @override
  String get captureDocumentOrImage => 'Capture a document or image';

  @override
  String get checkConnection => 'Check Connection';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get chooseDifferentFile => 'Choose Different File';

  @override
  String get goBack => 'Go Back';

  @override
  String get technicalDetails => 'Technical Details';
}
