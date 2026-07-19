import React, { useState } from "react";
import { Image, Modal, StyleSheet, Text, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { Screen } from "../components/Layout";
import {
  ApprovalButton,
  DepthButton,
  InfoButton,
} from "../components/DepthButton";
import { BorderedTextField } from "../components/BorderedTextField";
import { AppColors, ButtonColors, Fonts, TextColors } from "../theme";
import { S } from "../strings";
import { Nav, Rt } from "../navigation";
import { addCapture } from "../store";
import { uuidLike } from "../uuid";

// Tree image review: NOTE dialog + Approve/Reject. Approve saves the capture and
// returns to the capture screen (matching the Android flow).
export default function TreeImageReviewScreen() {
  const nav = useNavigation<Nav<"TreeImageReview">>();
  const route = useRoute<Rt<"TreeImageReview">>();
  const { sessionId, photoUri, lat, lon } = route.params;
  const [note, setNote] = useState("");
  const [draftNote, setDraftNote] = useState("");
  const [noteOpen, setNoteOpen] = useState(false);

  async function approve() {
    await addCapture({
      id: uuidLike(),
      sessionId,
      lat,
      lon,
      note,
      photoPath: photoUri,
      capturedAt: new Date().toISOString(),
      absStepCount: 0,
      deltaStepCount: 0,
      uploaded: false,
    });
    nav.goBack();
  }

  return (
    <Screen>
      {/* top bar with NOTE button */}
      <View style={styles.topBar}>
        <View style={styles.cell} />
        <View style={[styles.cell, styles.center]}>
          <DepthButton
            colors={ButtonColors.Default}
            width={100}
            height={56}
            onPress={() => {
              setDraftNote(note);
              setNoteOpen(true);
            }}>
            <Text style={styles.noteLabel}>{S.note}</Text>
          </DepthButton>
        </View>
        <View style={styles.cell} />
      </View>

      <View style={styles.imageWrap}>
        {photoUri ? (
          <Image source={{ uri: photoUri }} style={styles.img} />
        ) : (
          <View style={[styles.img, styles.placeholder]} />
        )}
      </View>

      <View style={styles.bottomBar}>
        <ApprovalButton
          approval={false}
          accessibilityLabel={S.rejectTree}
          onPress={() => nav.goBack()}
        />
        <View style={{ width: 24 }} />
        <ApprovalButton
          approval
          accessibilityLabel={S.approveTree}
          onPress={approve}
        />
        <View style={{ width: 24 }} />
        <InfoButton onPress={() => {}} />
      </View>

      <Modal visible={noteOpen} transparent animationType="fade">
        <View style={styles.modalWrap}>
          <View style={styles.dialog}>
            <Text style={styles.dialogTitle}>{S.addNoteToTree}</Text>
            <BorderedTextField
              style={styles.input}
              placeholder=""
              value={draftNote}
              onChangeText={setDraftNote}
            />
            <View style={styles.dialogButtons}>
              <ApprovalButton
                approval={false}
                size={40}
                accessibilityLabel="Cancel note"
                onPress={() => setNoteOpen(false)}
              />
              <View style={{ width: 24 }} />
              <ApprovalButton
                approval
                size={40}
                accessibilityLabel={S.saveNote}
                onPress={() => {
                  setNote(draftNote);
                  setNoteOpen(false);
                }}
              />
            </View>
          </View>
        </View>
      </Modal>
    </Screen>
  );
}

const styles = StyleSheet.create({
  topBar: {
    flexDirection: "row",
    alignItems: "center",
    height: 80,
    paddingHorizontal: 4,
  },
  cell: { flex: 1, justifyContent: "center" },
  center: { alignItems: "center" },
  noteLabel: {
    color: TextColors.primaryText,
    fontSize: 14,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
  },
  imageWrap: { flex: 1 },
  img: { flex: 1, resizeMode: "contain" },
  placeholder: { backgroundColor: "#000" },
  bottomBar: {
    flexDirection: "row",
    justifyContent: "center",
    alignItems: "center",
    paddingVertical: 16,
    backgroundColor: AppColors.Gray,
  },
  modalWrap: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.6)",
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  dialog: {
    width: "100%",
    backgroundColor: AppColors.Gray,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: AppColors.Green,
    padding: 20,
  },
  dialogTitle: {
    color: TextColors.primaryText,
    fontSize: 16,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
    marginBottom: 12,
  },
  input: { marginBottom: 16 },
  dialogButtons: { flexDirection: "row", justifyContent: "center" },
});
