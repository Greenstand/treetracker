import React from "react";
import { Image, Pressable, StyleSheet, Text, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { S } from "../strings";
import { Nav, Rt } from "../navigation";
import { addUser } from "../store";
import { getSignupDraft } from "../signupDraft";
import { uuidLike } from "../uuid";

// Selfie review -> creates the user and enters the Dashboard.
export default function ImageReviewScreen() {
  const nav = useNavigation<Nav<"ImageReview">>();
  const route = useRoute<Rt<"ImageReview">>();
  const { photoUri } = route.params;

  async function approve() {
    const d = getSignupDraft();
    const wallet = (d.value || uuidLike()).trim();
    await addUser({
      uuid: uuidLike(),
      firstName: d.firstName,
      lastName: d.lastName,
      phone: d.type === "PHONE" ? d.value : undefined,
      email: d.type === "EMAIL" ? d.value : undefined,
      photoPath: photoUri,
      wallet,
    });
    nav.reset({ index: 0, routes: [{ name: "Dashboard" }] });
  }

  return (
    <View style={styles.root}>
      {photoUri ? (
        <Image source={{ uri: photoUri }} style={styles.img} />
      ) : (
        <View style={[styles.img, styles.placeholder]}>
          <Text style={{ color: "#fff" }}>Selfie</Text>
        </View>
      )}
      <View style={styles.controls}>
        <Pressable
          accessibilityLabel={S.approveSelfie}
          accessibilityRole="button"
          onPress={approve}
          style={styles.approve}>
          <Text style={styles.approveText}>{"✓"}</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#000" },
  img: { flex: 1, resizeMode: "cover" },
  placeholder: { alignItems: "center", justifyContent: "center" },
  controls: {
    flexDirection: "row",
    justifyContent: "center",
    paddingVertical: 24,
    backgroundColor: "#000",
  },
  approve: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: "#2E7D32",
    alignItems: "center",
    justifyContent: "center",
  },
  approveText: { color: "#fff", fontSize: 34, fontWeight: "bold" },
});
