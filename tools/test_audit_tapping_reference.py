import unittest
import audit_tapping_reference as audit


def row(hand="Left", diagnosed="no"):
    return {"filename": f"2026-10-19T10-00-00-000Z1-task2-{hand.lower()}.webm",
            "hand": hand, "diagnosed": diagnosed, "age": "70", "gender": "female", "Rating": "1",
            **{f: "FALSE" for f in audit.FLAGS}, **{f: "1.5" for f in audit.FEATURES}}


class AuditTests(unittest.TestCase):
    def test_rate_candidate_keeps_hands_and_quality_sensitivity_separate(self):
        left, right, flagged, pd = row(), row("Right"), row(), row(diagnosed="yes")
        left["frequency_mean_trimmed"] = "2"
        right["frequency_mean_trimmed"] = "4"
        flagged["frequency_mean_trimmed"] = "6"
        flagged[audit.FLAGS[0]] = "TRUE"
        result = audit.rate_candidate([left, right, flagged, pd])
        self.assertEqual(result["hands"]["Left"]["all_no_pd_rows"]["recording_weighted"]["median"], 4)
        self.assertEqual(result["hands"]["Right"]["all_no_pd_rows"]["recording_weighted"]["median"], 4)
        clean = result["hands"]["Left"]["no_expert_difficulty_flags"]
        self.assertEqual(clean["recording_weighted"]["median"], 2)
        self.assertIsNone(clean["independent_participant_count"])
        self.assertFalse(result["patient_display_allowed"])

    def test_rate_candidate_reports_repeat_weighting_and_linear_percentiles(self):
        rows = []
        for filename, rate in (("NIH001-a-left.mp4", 1), ("NIH001-b-left.mp4", 3),
                               ("NIH002-a-left.mp4", 9)):
            item = row()
            item.update(filename=filename, frequency_mean_trimmed=str(rate))
            rows.append(item)
        result = audit.rate_candidate(rows)["hands"]["Left"]["all_no_pd_rows"]
        self.assertEqual(result["recording_weighted"]["median"], 3)
        self.assertEqual(result["filename_group_medians_sensitivity_only"]["median"], 5.5)
        self.assertAlmostEqual(result["recording_weighted"]["p05"], 1.2)
        self.assertEqual(result["filename_group_sizes"], {2: 1, 1: 1})

    def test_rate_candidate_empty_stratum_and_nonpositive_rate(self):
        item = row()
        item[audit.FLAGS[0]] = "TRUE"
        result = audit.rate_candidate([item])["hands"]["Left"]["no_expert_difficulty_flags"]
        self.assertFalse(result["recording_weighted"]["available"])
        item["frequency_mean_trimmed"] = "0"
        with self.assertRaises(ValueError):
            audit.rate_candidate([item])

    def test_hands_are_not_independent_people(self):
        result = audit.summarize([row(), row("Right"), row(diagnosed="yes")])
        self.assertEqual(result["control_rows"], 2)
        self.assertEqual(result["control_author_rule_groups"], 1)
        self.assertEqual(result["control_consensus_ratings"], {"1": 2})

    def test_repeated_groups_and_metadata_conflicts_are_visible(self):
        other = row()
        other["age"] = "71"
        result = audit.summarize([row(), row("Right"), other, row("Right")])
        self.assertEqual(result["control_group_size_distribution"], {4: 1})
        self.assertEqual(result["control_groups_with_conflicting_age_or_gender"], 1)
        self.assertEqual(result["control_unique_file_hand_keys"], 2)

    def test_any_expert_flag_counted_once(self):
        data = row()
        data[audit.FLAGS[0]] = data[audit.FLAGS[1]] = "TRUE"
        self.assertEqual(audit.summarize([data])["control_rows_any_expert_difficulty"], 1)

    def test_invalid_or_nonfinite_metadata_fails(self):
        for field, value in (("diagnosed", "unknown"), ("hand", "unknown"), ("age", ""),
                             (audit.FLAGS[0], "maybe"), (audit.FEATURES[0], "NaN")):
            data = row()
            data[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                audit.summarize([data])

    def test_grouping_and_age_boundaries(self):
        self.assertEqual(audit.author_group("NIH123-task2-left.mp4"), "NIH123")
        self.assertEqual(audit.author_group("NIH123"), "NIH123")
        data = row()
        data["age"] = "69"
        result = audit.summarize([data])
        self.assertEqual(result["control_row_age_bands_by_hand"]["Left"]["60_69"], 1)
        self.assertEqual(result["control_row_age_bands_by_hand"]["Left"]["70_plus"], 0)


if __name__ == "__main__":
    unittest.main()
