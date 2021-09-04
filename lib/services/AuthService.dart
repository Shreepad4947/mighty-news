import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mighty_news_firebase/models/UserModel.dart';
import 'package:mighty_news_firebase/utils/Common.dart';
import 'package:mighty_news_firebase/utils/Constants.dart' as theme;
import 'package:mighty_news_firebase/utils/ModelKeys.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:the_apple_sign_in/the_apple_sign_in.dart';

import '../main.dart';

final GoogleSignIn googleSignIn = GoogleSignIn();

Future<void> signInWithGoogle() async {
  GoogleSignInAccount? googleSignInAccount = await googleSignIn.signIn();

  if (googleSignInAccount != null) {
    //region Google Sign In
    final GoogleSignInAuthentication googleSignInAuthentication = await googleSignInAccount.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleSignInAuthentication.accessToken,
      idToken: googleSignInAuthentication.idToken,
    );

    final UserCredential authResult = await auth.signInWithCredential(credential);
    final User user = authResult.user!;

    assert(!user.isAnonymous);
    assert(await user.getIdToken() != null);

    final User currentUser = auth.currentUser!;
    assert(user.uid == currentUser.uid);

    signOutGoogle();
    //endregion

    await loginFromFirebaseUser(user, theme.LoginTypeGoogle);
  } else {
    throw errorSomethingWentWrong;
  }
}

Future<UserModel> signInWithEmail(String email, String password) async {
  if (await userService.isUserExist(email, theme.LoginTypeApp)) {
    UserCredential userCredential = await auth.signInWithEmailAndPassword(email: email, password: password);

    if (userCredential != null && userCredential.user != null) {
      UserModel userModel = UserModel();

      User user = userCredential.user!;

      return await userService.userByEmail(user.email).then((value) async {
        log('Signed in');

        userModel = value;

        await setValue(theme.PASSWORD, password);
        await setValue(theme.LOGIN_TYPE, theme.LoginTypeApp);
        //
        await updateUserData(userModel);
        //
        await setUserDetailPreference(userModel);

        return userModel;
      }).catchError((e) {
        throw e;
      });
    } else {
      throw errorSomethingWentWrong;
    }
  } else {
    throw 'You are not registered with us';
  }
}

Future<void> signUpWithEmail(String name, String email, String password) async {
  UserCredential userCredential = await auth.createUserWithEmailAndPassword(email: email, password: password);

  if (userCredential != null && userCredential.user != null) {
    User currentUser = userCredential.user!;
    UserModel userModel = UserModel();

    /// Create user
    userModel.id = currentUser.uid;
    userModel.email = currentUser.email;
    userModel.name = name;
    userModel.image = '';
    userModel.loginType = theme.LoginTypeApp;
    userModel.isNotificationOn = true;
    userModel.appLanguage = theme.DefaultLanguage;
    userModel.themeIndex = 0;
    userModel.updatedAt = DateTime.now();
    userModel.createdAt = DateTime.now();

    userModel.isAdmin = false;
    userModel.isTester = false;
    userModel.isNotificationOn = true;

    userModel.oneSignalPlayerId = getStringAsync(theme.PLAYER_ID);

    await userService.addDocumentWithCustomId(currentUser.uid, userModel.toJson()).then((value) async {
      log('Signed up');
      await signInWithEmail(email, password).then((value) {
        //
      });
    }).catchError((e) {
      throw e;
    });
  } else {
    throw errorSomethingWentWrong;
  }
}

Future<void> changePassword(String newPassword) async {
  await FirebaseAuth.instance.currentUser!.updatePassword(newPassword).then((value) async {
    await setValue(theme.PASSWORD, newPassword);
  });
}

Future<void> setUserDetailPreference(UserModel userModel) async {
  await setValue(theme.USER_ID, userModel.id);
  await setValue(theme.FULL_NAME, userModel.name);
  await setValue(theme.USER_EMAIL, userModel.email);
  await setValue(theme.PROFILE_IMAGE, userModel.image.validate());
  await setValue(theme.IS_ADMIN, userModel.isAdmin.validate());
  await setValue(theme.IS_TESTER, userModel.isTester.validate());
  if (userModel.bookmarks != null) await setValue(theme.BOOKMARKS, jsonEncode(userModel.bookmarks));

  await setBookmarkList();
  postViewedList.clear();

  appStore.setLoggedIn(true);
  appStore.setUserId(userModel.id);
  appStore.setFullName(userModel.name);
  appStore.setUserEmail(userModel.email);
  appStore.setUserProfile(userModel.image);

  appStore.setAdmin(userModel.isAdmin.validate());
  appStore.setTester(userModel.isTester.validate());
}

Future<void> setBookmarkList() async {
  if (getStringAsync(theme.BOOKMARKS).isNotEmpty) {
    Iterable? it = jsonDecode(getStringAsync(theme.BOOKMARKS));

    if (it != null && it.isNotEmpty) {
      bookmarkList.clear();
      bookmarkList.addAll(it.map((e) => e.toString()).toList());
    }
  }
}

Future<void> updateUserData(UserModel user) async {
  //
  /// Update user data
  userService.updateDocument({
    UserKeys.oneSignalPlayerId: getStringAsync(theme.PLAYER_ID),
    CommonKeys.updatedAt: DateTime.now(),
    UserKeys.isNotificationOn: user.isNotificationOn.validate(value: true),
  }, user.id);

  await setValue(THEME_MODE_INDEX, user.themeIndex.validate());

  appStore.setNotification(user.isNotificationOn.validate(value: true));
  appStore.setLanguage(user.appLanguage.validate(value: theme.DefaultLanguage));

  ///
  setTheme();
}

Future<void> logout(BuildContext context, {Function? onLogout}) async {
  await removeKey(theme.IS_LOGGED_IN);
  await removeKey(theme.IS_ADMIN);
  await removeKey(theme.USER_ID);
  await removeKey(theme.FULL_NAME);
  await removeKey(theme.USER_EMAIL);
  await removeKey(theme.USER_ROLE);
  await removeKey(theme.PASSWORD);
  await removeKey(theme.PROFILE_IMAGE);
  await removeKey(theme.IS_NOTIFICATION_ON);
  await removeKey(theme.IS_REMEMBERED);
  await removeKey(theme.LANGUAGE);
  await removeKey(theme.PLAYER_ID);
  await removeKey(theme.IS_SOCIAL_LOGIN);
  await removeKey(theme.LOGIN_TYPE);
  await removeKey(theme.POST_VIEWED_LIST);
  await removeKey(theme.BOOKMARKS);

  bookmarkList.clear();
  postViewedList.clear();

  if (getBoolAsync(theme.IS_SOCIAL_LOGIN) || getStringAsync(theme.LOGIN_TYPE) == theme.LoginTypeOTP || !getBoolAsync(theme.IS_REMEMBERED)) {
    await removeKey(theme.PASSWORD);
    await removeKey(theme.USER_EMAIL);
  }

  appStore.setLoggedIn(false);
  appStore.setUserId('');
  appStore.setFullName('');
  appStore.setUserEmail('');
  appStore.setUserProfile('');

  onLogout?.call();
}

Future<void> signOutGoogle() async {
  await googleSignIn.signOut();
}

Future<void> loginWithOTP(BuildContext context, String phoneNumber) async {
  return await auth.verifyPhoneNumber(
    phoneNumber: phoneNumber,
    verificationCompleted: (PhoneAuthCredential credential) async {
      //finish(context);
      //await showInDialog(context, child: OTPDialog(isCodeSent: true, phoneNumber: phoneNumber, credential: credential), backgroundColor: Colors.black);
    },
    verificationFailed: (FirebaseAuthException e) {
      if (e.code == 'invalid-phone-number') {
        toast('The provided phone number is not valid.');
        throw 'The provided phone number is not valid.';
      } else {
        toast(e.toString());
        throw e.toString();
      }
    },
    codeSent: (String verificationId, int? resendToken) async {
      finish(context);
      //await showInDialog(context, child: OTPDialog(verificationId: verificationId, isCodeSent: true, phoneNumber: phoneNumber), barrierDismissible: false);
    },
    codeAutoRetrievalTimeout: (String verificationId) {
      //
    },
  );
}

/// Sign-In with Apple.
Future<void> appleLogIn() async {
  if (await TheAppleSignIn.isAvailable()) {
    AuthorizationResult result = await TheAppleSignIn.performRequests([
      AppleIdRequest(requestedScopes: [Scope.email, Scope.fullName])
    ]);
    switch (result.status) {
      case AuthorizationStatus.authorized:
        final appleIdCredential = result.credential!;
        final oAuthProvider = OAuthProvider('apple.com');
        final credential = oAuthProvider.credential(
          idToken: String.fromCharCodes(appleIdCredential.identityToken!),
          accessToken: String.fromCharCodes(appleIdCredential.authorizationCode!),
        );
        final authResult = await auth.signInWithCredential(credential);
        final user = authResult.user!;

        if (result.credential!.email != null) {
          await saveAppleData(result);
        }

        await loginFromFirebaseUser(
          user,
          theme.LoginTypeApple,
          fullName: '${getStringAsync('appleGivenName')} ${getStringAsync('appleFamilyName')}',
        );
        break;
      case AuthorizationStatus.error:
        throw ("Sign in failed: ${result.error!.localizedDescription}");
        break;
      case AuthorizationStatus.cancelled:
        throw ('User cancelled');
        break;
    }
  } else {
    throw ('Apple SignIn is not available for your device');
  }
}

/// UserData provided only 1st time..

Future<void> saveAppleData(AuthorizationResult result) async {
  await setValue('appleEmail', result.credential!.email);
  await setValue('appleGivenName', result.credential!.fullName!.givenName);
  await setValue('appleFamilyName', result.credential!.fullName!.familyName);
}

Future<void> loginFromFirebaseUser(User currentUser, String loginType, {String? fullName}) async {
  UserModel userModel = UserModel();

  if (await userService.isUserExist(currentUser.email, loginType)) {
    //
    ///Return user data
    await userService.userByEmail(currentUser.email).then((user) async {
      userModel = user;

      await updateUserData(userModel);
    }).catchError((e) {
      throw e;
    });
  } else {
    /// Create user
    userModel.id = currentUser.uid;
    userModel.email = currentUser.email;
    userModel.name = (currentUser.displayName) ?? fullName;
    userModel.image = currentUser.photoURL;
    userModel.loginType = loginType;
    userModel.updatedAt = DateTime.now();
    userModel.createdAt = DateTime.now();

    userModel.isAdmin = false;
    userModel.isTester = false;
    userModel.isNotificationOn = true;

    userModel.oneSignalPlayerId = getStringAsync(theme.PLAYER_ID);

    await userService.addDocumentWithCustomId(currentUser.uid, userModel.toJson()).then((value) {
      //
    }).catchError((e) {
      throw e;
    });
  }

  await setValue(theme.LOGIN_TYPE, loginType);
  setUserDetailPreference(userModel);
}
