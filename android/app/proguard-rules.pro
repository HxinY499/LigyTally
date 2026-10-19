# shared_preferences_android 2.5.x resolves suspend methods through JNI.
# The JNI signature embeds the original binary name of the Kotlin
# continuation interface. R8 must not rename these types, otherwise a
# release build fails with NoSuchMethodError on SharedPreferences access.
-keep interface kotlin.coroutines.Continuation { *; }
-keep interface kotlin.coroutines.CoroutineContext { *; }

# Keep the generated registrar classes as well. The JNI bridge looks these
# classes up by their original names; the annotation on the generated class
# is not enough when its suspend method parameter types are obfuscated.
-keep class io.flutter.plugins.sharedpreferences.SharedPreferencesApiRegistrar { *; }
-keep class io.flutter.plugins.sharedpreferences.SharedPreferencesAsyncApiRegistrar { *; }
