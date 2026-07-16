import React, { useEffect, useRef, useState } from "react";
import { StyleSheet, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { CameraView, useCameraPermissions } from "expo-camera";
import * as Location from "expo-location";
import { Screen } from "../components/Layout";
import { ArrowButton, CaptureButton, InfoButton } from "../components/DepthButton";
import { AppColors } from "../theme";
import { S } from "../strings";
import { Nav, Rt } from "../navigation";

// Tree capture. "Take tree photo" is location-gated: disabled until a GPS fix is
// available (the emulator fix is seeded by the e2e via setGeolocation).
export default function TreeCaptureScreen() {
  const nav = useNavigation<Nav<"TreeCapture">>();
  const route = useRoute<Rt<"TreeCapture">>();
  const camRef = useRef<CameraView>(null);
  const [perm, requestPerm] = useCameraPermissions();
  const [coords, setCoords] = useState<{ lat: number; lon: number } | null>(
    null,
  );

  useEffect(() => {
    if (!perm?.granted) requestPerm();
  }, [perm?.granted]);

  useEffect(() => {
    let sub: Location.LocationSubscription | undefined;
    (async () => {
      try {
        await Location.requestForegroundPermissionsAsync();
        const cur = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        });
        setCoords({ lat: cur.coords.latitude, lon: cur.coords.longitude });
        sub = await Location.watchPositionAsync(
          { accuracy: Location.Accuracy.Balanced, distanceInterval: 1 },
          (loc) =>
            setCoords({ lat: loc.coords.latitude, lon: loc.coords.longitude }),
        );
      } catch {
        /* no location yet -> capture stays disabled */
      }
    })();
    return () => sub?.remove();
  }, []);

  async function capture() {
    if (!coords) return;
    let uri = "";
    try {
      const photo = await camRef.current?.takePictureAsync({ quality: 0.5 });
      uri = photo?.uri ?? "";
    } catch {
      /* ignore */
    }
    nav.navigate("TreeImageReview", {
      sessionId: route.params.sessionId,
      photoUri: uri,
      lat: coords.lat,
      lon: coords.lon,
    });
  }

  return (
    <Screen>
      <View style={styles.camWrap}>
        {perm?.granted ? (
          <CameraView ref={camRef} style={StyleSheet.absoluteFill} facing="back" />
        ) : (
          <View style={[StyleSheet.absoluteFill, styles.placeholder]} />
        )}
      </View>
      <View style={styles.bottomBar}>
        <View style={styles.cell}>
          <ArrowButton isLeft onPress={() => nav.navigate("Dashboard")} />
        </View>
        <View style={[styles.cell, styles.center]}>
          <CaptureButton
            accessibilityLabel={S.takeTreePhoto}
            enabled={!!coords}
            onPress={capture}
          />
        </View>
        <View style={[styles.cell, styles.right]}>
          <InfoButton onPress={() => {}} />
        </View>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  camWrap: { flex: 1, overflow: "hidden" },
  placeholder: { backgroundColor: "#000" },
  bottomBar: {
    flexDirection: "row",
    alignItems: "center",
    height: 80,
    paddingHorizontal: 4,
    backgroundColor: AppColors.Gray,
  },
  cell: { flex: 1, justifyContent: "center" },
  center: { alignItems: "center" },
  right: { alignItems: "flex-end" },
});
