import React from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Nav, Rt } from "../navigation";
import { getState } from "../store";

// Wallet select. The wallet card shows the user's name (same "Test User" anchor
// the e2e taps), matching the Android WalletSelectScreen behavior.
export default function WalletSelectScreen() {
  const nav = useNavigation<Nav<"WalletSelect">>();
  const route = useRoute<Rt<"WalletSelect">>();
  const user = getState().users.find((u) => u.uuid === route.params.userUuid);
  const name = user ? `${user.firstName} ${user.lastName}`.trim() : "";

  return (
    <View style={styles.root}>
      <View style={styles.list}>
        <Pressable style={[styles.card, styles.cardSel]}>
          <Text style={styles.name}>{name}</Text>
        </Pressable>
      </View>
      <ActionBar
        onBack={() => nav.goBack()}
        forwardEnabled={!!user}
        onForward={() =>
          user &&
          nav.navigate("AddOrg", { userUuid: user.uuid, wallet: user.wallet })
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#fff" },
  list: { flex: 1, padding: 24, paddingTop: 60, gap: 16 },
  card: {
    padding: 24,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#2E7D32",
    alignItems: "center",
  },
  cardSel: { backgroundColor: "#C8E6C9" },
  name: { fontSize: 20, fontWeight: "600", color: "#1B5E20" },
});
