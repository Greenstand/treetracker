import React, { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { LANGUAGES, Language } from "../strings";
import { Nav } from "../navigation";

export default function LanguageScreen() {
  const nav = useNavigation<Nav<"Language">>();
  const [selected, setSelected] = useState<Language>("ENGLISH");

  return (
    <View style={styles.root}>
      <ScrollView contentContainerStyle={styles.list}>
        {LANGUAGES.map((lang) => (
          <Pressable
            key={lang}
            onPress={() => setSelected(lang)}
            style={[styles.item, selected === lang && styles.itemSel]}>
            <Text style={styles.itemText}>{lang}</Text>
          </Pressable>
        ))}
      </ScrollView>
      <ActionBar onForward={() => nav.navigate("Credential")} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#fff" },
  list: { padding: 24, paddingTop: 80, gap: 16 },
  item: {
    paddingVertical: 18,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#2E7D32",
    alignItems: "center",
  },
  itemSel: { backgroundColor: "#C8E6C9" },
  itemText: { fontSize: 20, fontWeight: "600", color: "#1B5E20" },
});
