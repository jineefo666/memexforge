import 'dart:io';

String defaultWorkbenchWorkingDirectory() {
  final home = Platform.environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) return home;

  final userProfile = Platform.environment['USERPROFILE']?.trim();
  if (userProfile != null && userProfile.isNotEmpty) return userProfile;

  return Directory.current.path;
}
