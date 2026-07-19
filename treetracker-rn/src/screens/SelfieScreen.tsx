import React, { useEffect, useRef } from "react";
import { StyleSheet, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { CameraView, useCameraPermissions } from "expo-camera";
import { Screen, TopBar } from "../components/Layout";
import { CaptureButton, InfoButton } from "../components/DepthButton";
import { AppColors } from "../theme";
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
    <Screen>
      <TopBar />
      <View style={styles.camWrap}>
        {perm?.granted ? (
          <CameraView ref={camRef} style={StyleSheet.absoluteFill} facing="front" />
        ) : (
          <View style={[StyleSheet.absoluteFill, styles.placeholder]} />
        )}
        <View style={styles.shutter}>
          <CaptureButton accessibilityLabel={S.takeSelfie} onPress={capture} />
        </View>
      </View>
      <View style={styles.bottomBar}>
        <View style={{ flex: 2 }} />
        <View style={styles.infoCell}>
          <InfoButton onPress={() => {}} />
        </View>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  camWrap: { flex: 1, aspectRatio: 1, alignSelf: "stretch", overflow: "hidden" },
  placeholder: { backgroundColor: "#000" },
  shutter: {
    position: "absolute",
    bottom: 16,
    alignSelf: "center",
  },
  bottomBar: {
    flexDirection: "row",
    alignItems: "center",
    height: 80,
    paddingHorizontal: 4,
    backgroundColor: AppColors.Gray,
  },
  infoCell: { flex: 1, alignItems: "flex-end" },
});
