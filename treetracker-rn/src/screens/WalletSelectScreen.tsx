import React from "react";
import { Image, StyleSheet, Text, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Screen, TopBar } from "../components/Layout";
import { OrangeAddButton } from "../components/DepthButton";
import { AppColors, Fonts, TextColors } from "../theme";
import { Nav, Rt } from "../navigation";
import { getState } from "../store";

// Wallet select. The wallet card shows the user's name (same anchor the e2e taps),
// matching the Android WalletSelectScreen.
export default function WalletSelectScreen() {
  const nav = useNavigation<Nav<"WalletSelect">>();
  const route = useRoute<Rt<"WalletSelect">>();
  const user = getState().users.find((u) => u.uuid === route.params.userUuid);
  const name = user ? `${user.firstName} ${user.lastName}`.trim() : "";

  const userImage = user?.photoPath ? (
    <Image source={{ uri: user.photoPath }} style={styles.userImage} />
  ) : (
    <View style={[styles.userImage, styles.userPlaceholder]} />
  );

  return (
    <Screen>
      <TopBar left={userImage} />
      <View style={styles.list}>
        <View style={[styles.card, styles.cardSel]}>
          {user?.photoPath ? (
            <Image source={{ uri: user.photoPath }} style={styles.photo} />
          ) : (
            <View style={[styles.photo, styles.photoPlaceholder]} />
          )}
          <Text numberOfLines={1} style={styles.name}>
            {name}
          </Text>
          <Text numberOfLines={1} style={styles.wallet}>
            {user?.wallet}
          </Text>
        </View>
      </View>
      <ActionBar
        onBack={() => nav.goBack()}
        center={<OrangeAddButton onPress={() => {}} />}
        forwardEnabled={!!user}
        onForward={() =>
          user &&
          nav.navigate("AddOrg", { userUuid: user.uuid, wallet: user.wallet })
        }
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  userImage: {
    width: 70,
    height: 70,
    borderRadius: 10,
    marginLeft: 12,
  },
  userPlaceholder: { backgroundColor: AppColors.DeepGray },
  list: { flex: 1, padding: 10, alignItems: "flex-start" },
  card: {
    width: "46%",
    backgroundColor: AppColors.GrayShadow,
    borderRadius: 10,
    padding: 8,
    borderWidth: 1,
    borderColor: "transparent",
  },
  cardSel: { borderColor: AppColors.Green },
  photo: { width: "100%", aspectRatio: 1, borderRadius: 10, marginBottom: 8 },
  photoPlaceholder: { backgroundColor: AppColors.DeepGray },
  name: {
    color: TextColors.lightText,
    fontSize: 12,
    fontWeight: "600",
    fontFamily: Fonts.regular,
    paddingHorizontal: 4,
  },
  wallet: {
    color: TextColors.lightText,
    fontSize: 12,
    fontWeight: "600",
    fontFamily: Fonts.regular,
    paddingHorizontal: 4,
  },
});
