#include <jni.h>
#include <string>

extern "C" {
long long aether_mix_packet_create(const char* json, int fd);
int aether_mix_packet_is_ready(long long handle);
const char* aether_mix_packet_last_error(long long handle);
int aether_mix_packet_stop(long long handle);
}

static std::string text(JNIEnv* env, jstring value) {
    if (!value) return {};
    const char* p = env->GetStringUTFChars(value, nullptr);
    if (!p) return {};
    std::string out(p);
    env->ReleaseStringUTFChars(value, p);
    return out;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_forwin_vpn_mix_MixPacketStack_00024Companion_nativeCreate(JNIEnv* env, jobject, jstring json, jint fd) {
    const auto s = text(env, json);
    if (s.empty()) return -1;
    return static_cast<jlong>(aether_mix_packet_create(s.c_str(), fd));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_forwin_vpn_mix_MixPacketStack_00024Companion_nativeCreateError(JNIEnv* env, jobject, jlong code) {
    const char* message = code == -2 ? "panic in Mix packet bridge" :
        (code == -1 ? "invalid Mix packet configuration or descriptor" : "failed to create Mix packet bridge");
    return env->NewStringUTF(message);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_forwin_vpn_mix_MixPacketStack_00024Companion_nativeIsReady(JNIEnv*, jobject, jlong handle) {
    return aether_mix_packet_is_ready(handle) != 0;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_forwin_vpn_mix_MixPacketStack_00024Companion_nativeLastError(JNIEnv* env, jobject, jlong handle) {
    const char* error = aether_mix_packet_last_error(handle);
    return env->NewStringUTF(error ? error : "");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_forwin_vpn_mix_MixPacketStack_00024Companion_nativeStop(JNIEnv*, jobject, jlong handle) {
    return aether_mix_packet_stop(handle);
}
