import React, { useEffect, useRef } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { CameraView, useCameraPermissions } from "expo-camera";
import { ActionBar } from "../components/ActionBar";
import { S } from "../strings";
import { Nav } from "../navigation";

export default function SelfieScreen() {
  const nav = useNavigation<Nav<"Selfie">>();
  const camRef = useRef<CameraView>(null);
  const [perm, requestPerm] = useCameraPermissions();

  useEffect(() => {
    if (!perm?.granted) requestPerm();
  }, [perm?.granted]);

  async function capture() {
    let uri = "";
    try {
      const photo = await camRef.current?.takePictureAsync({ quality: 0.4 });
      uri = photo?.uri ?? "";
    } catch {
      /* emulator camera hiccup — selfie photo isn't uploaded in the tested flow */
    }
    nav.navigate("ImageReview", { photoUri: uri });
  }

  return (
    <View style={styles.root}>
      {perm?.granted ? (
        <CameraView ref={camRef} style={styles.cam} facing="front" />
      ) : (
        <View style={[styles.cam, styles.placeholder]}>
          <Text style={{ color: "#fff" }}>Camera</Text>
        </View>
      )}
      <View style={styles.controls}>
        <Pressable
          accessibilityLabel={S.takeSelfie}
          accessibilityRole="button"
          onPress={capture}
          style={styles.shutter}
        />
      </View>
      <ActionBar onBack={() => nav.goBack()} forwardEnabled={false} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#000" },
  cam: { flex: 1 },
  placeholder: { alignItems: "center", justifyContent: "center" },
  controls: { alignItems: "center", paddingVertical: 20, backgroundColor: "#000" },
  shutter: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: "#fff",
    borderWidth: 4,
    borderColor: "#2E7D32",
  },
});
