import React, { useState } from "react";
import { ScrollView, StyleSheet } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Screen, TopBar } from "../components/Layout";
import { DepthTextButton } from "../components/DepthButton";
import { LANGUAGES, Language } from "../strings";
import { Nav } from "../navigation";

export default function LanguageScreen() {
  const nav = useNavigation<Nav<"Language">>();
  const [selected, setSelected] = useState<Language>("ENGLISH");

  return (
    <Screen>
      <TopBar />
      <ScrollView contentContainerStyle={styles.list}>
        {LANGUAGES.map((lang) => (
          <DepthTextButton
            key={lang}
            label={lang}
            width={156}
            height={80}
            style={styles.item}
            onPress={() => setSelected(lang)}
          />
        ))}
      </ScrollView>
      <ActionBar
        forwardEnabled={!!selected}
        onForward={() => nav.navigate("Credential")}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  list: {
    flexGrow: 1,
    alignItems: "center",
    justifyContent: "center",
    paddingVertical: 16,
  },
  item: { margin: 16 },
});
