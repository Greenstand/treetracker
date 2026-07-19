import React from "react";
import { Image, StyleSheet, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { ApprovalButton } from "../components/DepthButton";
import { AppColors } from "../theme";
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
        <View style={[styles.img, styles.placeholder]} />
      )}
      <View style={styles.controls}>
        <ApprovalButton
          approval={false}
          accessibilityLabel="Retake photo"
          onPress={() => nav.goBack()}
        />
        <View style={{ width: 24 }} />
        <ApprovalButton
          approval
          accessibilityLabel={S.approveSelfie}
          onPress={approve}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: AppColors.Gray },
  img: { flex: 1, resizeMode: "contain" },
  placeholder: { backgroundColor: "#000" },
  controls: {
    flexDirection: "row",
    justifyContent: "center",
    alignItems: "center",
    paddingVertical: 24,
    backgroundColor: AppColors.Gray,
  },
});
