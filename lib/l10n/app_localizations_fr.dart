// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Conduit';

  @override
  String get initializationFailed => 'Échec de l\'initialisation';

  @override
  String get retry => 'Réessayer';

  @override
  String get back => 'Retour';

  @override
  String get you => 'Vous';

  @override
  String get loadingProfile => 'Chargement du profil...';

  @override
  String get unableToLoadProfile => 'Impossible de charger le profil';

  @override
  String get pleaseCheckConnection => 'Veuillez vérifier votre connexion et réessayer';

  @override
  String get account => 'Compte';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get endYourSession => 'Terminer votre session';

  @override
  String get defaultModel => 'Modèle par défaut';

  @override
  String get autoSelect => 'Sélection automatique';

  @override
  String get loadingModels => 'Chargement des modèles...';

  @override
  String get failedToLoadModels => 'Échec du chargement des modèles';

  @override
  String get availableModels => 'Modèles disponibles';

  @override
  String get noResults => 'Aucun résultat';

  @override
  String get searchModels => 'Rechercher des modèles...';

  @override
  String get errorMessage => 'Une erreur s\'est produite. Veuillez réessayer.';

  @override
  String get loginButton => 'Connexion';

  @override
  String get menuItem => 'Paramètres';

  @override
  String dynamicContentWithPlaceholder(String name) {
    return 'Bienvenue, $name !';
  }

  @override
  String itemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '1 élément',
      zero: 'Aucun élément',
    );
    return '$_temp0';
  }

  @override
  String get closeButtonSemantic => 'Fermer';

  @override
  String get loadingContent => 'Chargement du contenu';

  @override
  String get noItems => 'Aucun élément';

  @override
  String get noItemsToDisplay => 'Aucun élément à afficher';

  @override
  String get loadMore => 'Charger plus';

  @override
  String get workspace => 'Espace de travail';

  @override
  String get recentFiles => 'Fichiers récents';

  @override
  String get knowledgeBase => 'Base de connaissances';

  @override
  String get noFilesYet => 'Pas encore de fichiers';

  @override
  String get uploadDocsPrompt => 'Importez des documents à utiliser dans vos conversations avec Conduit';

  @override
  String get uploadFirstFile => 'Importer votre premier fichier';

  @override
  String get knowledgeBaseEmpty => 'La base de connaissances est vide';

  @override
  String get createCollectionsPrompt => 'Créez des collections de documents liés pour une référence facile';

  @override
  String get chooseSourcePhoto => 'Choisir la source';

  @override
  String get takePhoto => 'Prendre une photo';

  @override
  String get chooseFromGallery => 'Choisir depuis vos photos';

  @override
  String get document => 'Document';

  @override
  String get documentHint => 'Fichier PDF, Word ou texte';

  @override
  String get uploadFileTitle => 'Importer un fichier';

  @override
  String fileUploadComingSoon(String type) {
    return 'Le téléversement de fichiers pour $type arrive bientôt !';
  }

  @override
  String get kbCreationComingSoon => 'La création de la base de connaissances arrive bientôt !';

  @override
  String get backToServerSetup => 'Retour à la configuration du serveur';

  @override
  String get connectedToServer => 'Connecté au serveur';

  @override
  String get signIn => 'Se connecter';

  @override
  String get enterCredentials => 'Entrez vos identifiants pour accéder à vos conversations IA';

  @override
  String get credentials => 'Identifiants';

  @override
  String get apiKey => 'Clé API';

  @override
  String get usernameOrEmail => 'Nom d\'utilisateur ou e‑mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get signInWithApiKey => 'Se connecter avec une clé API';

  @override
  String get connectToServer => 'Se connecter au serveur';

  @override
  String get enterServerAddress => 'Saisissez l\'adresse de votre serveur Open-WebUI pour commencer';

  @override
  String get serverUrl => 'URL du serveur';

  @override
  String get serverUrlHint => 'https://votre-serveur.com';

  @override
  String get enterServerUrlSemantic => 'Saisissez l\'URL ou l\'adresse IP de votre serveur';

  @override
  String get headerName => 'Nom de l\'en-tête';

  @override
  String get headerValue => 'Valeur de l\'en-tête';

  @override
  String get headerValueHint => 'api-key-123 ou jeton Bearer';

  @override
  String get addHeader => 'Ajouter l\'en-tête';

  @override
  String get maximumHeadersReached => 'Nombre maximal atteint';

  @override
  String get removeHeader => 'Supprimer l\'en-tête';

  @override
  String get connecting => 'Connexion en cours...';

  @override
  String get connectToServerButton => 'Se connecter au serveur';

  @override
  String get demoModeActive => 'Mode démo activé';

  @override
  String get skipServerSetupTryDemo => 'Ignorer la configuration et essayer la démo';

  @override
  String get enterDemo => 'Entrer en démo';

  @override
  String get demoBadge => 'Démo';

  @override
  String get serverNotOpenWebUI => 'Ceci ne semble pas être un serveur Open-WebUI.';

  @override
  String get serverUrlEmpty => 'L\'URL du serveur ne peut pas être vide';

  @override
  String get invalidUrlFormat => 'Format d\'URL invalide. Veuillez vérifier votre saisie.';

  @override
  String get onlyHttpHttps => 'Seuls les protocoles HTTP et HTTPS sont pris en charge.';

  @override
  String get serverAddressRequired => 'Adresse du serveur requise (ex. 192.168.1.10 ou example.com).';

  @override
  String get portRange => 'Le port doit être compris entre 1 et 65535.';

  @override
  String get invalidIpFormat => 'Format d\'IP invalide. Exemple : 192.168.1.10.';

  @override
  String get couldNotConnectGeneric => 'Connexion impossible. Vérifiez l\'adresse et réessayez.';

  @override
  String get weCouldntReachServer => 'Impossible d\'atteindre le serveur. Vérifiez la connexion et l\'état du serveur.';

  @override
  String get connectionTimedOut => 'Délai d\'attente dépassé. Le serveur est peut-être occupé ou bloqué.';

  @override
  String get useHttpOrHttpsOnly => 'Utilisez uniquement http:// ou https://.';

  @override
  String get loginFailed => 'Échec de la connexion';

  @override
  String get invalidCredentials => 'Nom d\'utilisateur ou mot de passe invalide. Réessayez.';

  @override
  String get serverRedirectingHttps => 'Le serveur redirige les requêtes. Vérifiez la configuration HTTPS.';

  @override
  String get unableToConnectServer => 'Impossible de se connecter au serveur. Vérifiez votre connexion.';

  @override
  String get requestTimedOut => 'Délai d\'attente dépassé. Réessayez.';

  @override
  String get genericSignInFailed => 'Connexion impossible. Vérifiez vos identifiants et le serveur.';

  @override
  String get skip => 'Ignorer';

  @override
  String get next => 'Suivant';

  @override
  String get done => 'Terminé';

  @override
  String get onboardStartTitle => 'Commencer une conversation';

  @override
  String get onboardStartSubtitle => 'Choisissez un modèle puis commencez à écrire. Touchez Nouveau chat à tout moment.';

  @override
  String get onboardStartBullet1 => 'Touchez le nom du modèle en haut pour changer';

  @override
  String get onboardStartBullet2 => 'Utilisez Nouveau chat pour réinitialiser le contexte';

  @override
  String get onboardAttachTitle => 'Ajouter du contexte';

  @override
  String get onboardAttachSubtitle => 'Améliorez les réponses en ajoutant des fichiers ou des images.';

  @override
  String get onboardAttachBullet1 => 'Fichiers : PDF, documents, jeux de données';

  @override
  String get onboardAttachBullet2 => 'Images : photos ou captures d\'écran';

  @override
  String get onboardSpeakTitle => 'Parlez naturellement';

  @override
  String get onboardSpeakSubtitle => 'Touchez le micro pour dicter avec retour visuel.';

  @override
  String get onboardSpeakBullet1 => 'Arrêtez à tout moment ; le texte partiel est conservé';

  @override
  String get onboardSpeakBullet2 => 'Idéal pour des notes rapides ou de longs prompts';

  @override
  String get onboardQuickTitle => 'Actions rapides';

  @override
  String get onboardQuickSubtitle => 'Utilisez le menu en haut à gauche pour ouvrir la liste des chats et la navigation.';

  @override
  String get onboardQuickBullet1 => 'Touchez le menu pour ouvrir les chats et la navigation';

  @override
  String get onboardQuickBullet2 => 'Accédez rapidement à Nouveau chat, Fichiers ou Profil';

  @override
  String get addAttachment => 'Ajouter une pièce jointe';

  @override
  String get tools => 'Outils';

  @override
  String get voiceInput => 'Entrée vocale';

  @override
  String get messageInputLabel => 'Saisie du message';

  @override
  String get messageInputHint => 'Saisissez votre message';

  @override
  String get messageHintText => 'Message...';

  @override
  String get stopGenerating => 'Arrêter la génération';

  @override
  String get send => 'Envoyer';

  @override
  String get sendMessage => 'Envoyer le message';

  @override
  String get file => 'Fichier';

  @override
  String get photo => 'Photo';

  @override
  String get camera => 'Appareil photo';

  @override
  String get apiUnavailable => 'Service API indisponible';

  @override
  String get unableToLoadImage => 'Impossible de charger l\'image';

  @override
  String notAnImageFile(String fileName) {
    return 'Ce n\'est pas un fichier image : $fileName';
  }

  @override
  String failedToLoadImage(String error) {
    return 'Échec du chargement de l\'image : $error';
  }

  @override
  String get invalidDataUrl => 'Format d\'URL de données invalide';

  @override
  String get failedToDecodeImage => 'Échec du décodage de l\'image';

  @override
  String get invalidImageFormat => 'Format d\'image invalide';

  @override
  String get emptyImageData => 'Données d\'image vides';

  @override
  String get offlineBanner => 'Vous êtes hors ligne. Certaines fonctions peuvent être limitées.';

  @override
  String get featureRequiresInternet => 'Cette fonctionnalité nécessite une connexion Internet';

  @override
  String get messagesWillSendWhenOnline => 'Les messages seront envoyés lorsque vous serez de nouveau en ligne';

  @override
  String get confirm => 'Confirmer';

  @override
  String get cancel => 'Annuler';

  @override
  String get ok => 'OK';

  @override
  String get inputField => 'Champ de saisie';

  @override
  String get captureDocumentOrImage => 'Capturer un document ou une image';

  @override
  String get checkConnection => 'Vérifier la connexion';

  @override
  String get openSettings => 'Ouvrir les réglages';

  @override
  String get chooseDifferentFile => 'Choisir un autre fichier';

  @override
  String get goBack => 'Retour';

  @override
  String get technicalDetails => 'Détails techniques';
}
