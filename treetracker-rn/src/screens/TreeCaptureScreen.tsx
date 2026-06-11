import React, { useEffect, useRef, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { CameraView, useCameraPermissions } from "expo-camera";
import * as Location from "expo-location";
import { ActionBar } from "../components/ActionBar";
import { S } from "../strings";
import { Nav, Rt } from "../navigation";

// Tree capture. The "Take tree photo" button is location-gated: disabled until a
// GPS fix is available (the emulator fix is seeded by the e2e via setGeolocation).
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

  const enabled = !!coords;

  return (
    <View style={styles.root}>
      {perm?.granted ? (
        <CameraView ref={camRef} style={styles.cam} facing="back" />
      ) : (
        <View style={[styles.cam, styles.placeholder]}>
          <Text style={{ color: "#fff" }}>Camera</Text>
        </View>
      )}
      <View style={styles.controls}>
        <Pressable
          accessibilityLabel={S.takeTreePhoto}
          accessibilityRole="button"
          accessibilityState={{ disabled: !enabled }}
          disabled={!enabled}
          onPress={capture}
          style={[styles.shutter, !enabled && styles.disabled]}
        />
      </View>
      <ActionBar
        onBack={() => nav.navigate("Dashboard")}
        forwardEnabled={false}
      />
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
  disabled: { opacity: 0.4 },
});
