# Spanish localization review for 1.6.0

Returned workbook: ghostWriter-Spanish-review-1.xlsx

Workbook SHA-256: `0301ebc882fef1b6a5f510c3c18d893b491af385477829e14afe97a2e4547466`

The returned workbook is preserved unchanged. Corrections take precedence over drafts; the translators entered their changes in the Spanish draft column in this return.

Imported 562 reviewed current catalog strings and the reviewed Welcome document, plus 1 follow-up draft(s) marked Needs review. 4 reviewed entries no longer match current source and were not imported. 148 workbook entries remain pending.

The Spanish interface release hold remains in place. New stylesheet documentation needs a Spanish draft and review in the next workbook. Existing unreviewed translations are retained as drafts, not newly approved. The English and bundled Help documents remain English until a complete Spanish manual is prepared.

Spanish Grade 1 remains the default. Grade 2 has not received a full translator braille test; it must not be described as validated.

## Translator follow-up

The five context questions have been answered. The following confirmations supersede the original workbook:

- Dismiss: Ocultar
- Editing: Edición
- Rounded: Redondeada
- Friendly Haunting Received: ¡Aparición amistosa recibida!
- Friendly hauntings: Apariciones amistosas

The support explanation now identifies optional purchases and states that they unlock no features. Its exact Spanish wording is a draft awaiting translator review:

ghostWriter no tiene anuncios ni suscripciones. Si te ayuda a escribir, puedes apoyar futuras actualizaciones con estas compras opcionales, llamadas «apariciones amistosas». No desbloquean ninguna función. Todas las opciones reciben el mismo agradecimiento.

Acknowledgements credits: Jose María Ortiz; Mónica Montes. The new Spanish translation section label also needs translator review.

## Questions to resolve

No original context questions remain unresolved.


## Reviewed entries whose source changed or was removed

- GW-0440: Choose how many columns and rows you want. The first row will name the columns.
- GW-0497: Every style sheet must contain version with the number 1. Existing version 1 files remain supported; older app builds may reject files containing the new optional properties. Optional top-level fields are body, headings, quote, code, list, table, page, title, subtitle, thematicBreak, header, footer, and differentFirstPage. Use the exact field names and capitalization. The headings object accepts keys 1 through 6, written in quotes, to style the resulting Word heading levels after any compilation heading changes.
- GW-0590: Paragraph styles accept firstLineIndent in points from 0 to 720, plus true or false for pageBreakBefore, pageBreakAfter, and keepWithNext. Omit a property to inherit its value. Page break after inserts a page break after the paragraph. The table object does not accept pageBreakBefore or pageBreakAfter; page breaks are not inserted inside table cells. Heading styles can use keepWithNext to stay with the following paragraph.
- GW-0628: Set differentFirstPage to true to leave the first page's header and footer blank. Headers, footers, and page numbering apply to the whole exported document, including compilations. Header and footer distances are 18 points from the page edge; leave sufficient page margins for their text. Chapter-specific headers, odd/even layouts, and numbering restarts are not supported.

## Pending export and interface entries

GW-0521, GW-0047, GW-0050, GW-0051, GW-0060, GW-0066, GW-0071, GW-0106, GW-0122, GW-0142, GW-0143, GW-0144, GW-0149, GW-0154, GW-0160, GW-0162, GW-0164, GW-0170, GW-0218, GW-0227, GW-0248, GW-0274, GW-0275, GW-0277, GW-0279, GW-0281, GW-0289, GW-0293, GW-0308, GW-0317, GW-0318, GW-0319, GW-0327, GW-0336, GW-0340, GW-0341, GW-0342, GW-0346, GW-0347, GW-0348, GW-0349, GW-0353, GW-0355, GW-0356, GW-0357, GW-0358, GW-0359, GW-0360, GW-0369, GW-0370, GW-0372, GW-0373, GW-0374, GW-0382, GW-0391, GW-0405, GW-0406, GW-0409, GW-0410, GW-0414, GW-0415, GW-0417, GW-0418, GW-0419, GW-0420, GW-0421, GW-0427, GW-0429, GW-0435, GW-0436, GW-0453, GW-0454, GW-0457, GW-0458, GW-0461, GW-0469, GW-0470, GW-0472, GW-0476, GW-0480, GW-0481, GW-0482, GW-0492, GW-0493, GW-0501, GW-0504, GW-0507, GW-0512, GW-0526, GW-0532, GW-0533, GW-0534, GW-0543, GW-0546, GW-0556, GW-0557, GW-0565, GW-0569, GW-0570, GW-0575, GW-0576, GW-0577, GW-0578, GW-0580, GW-0581, GW-0589, GW-0592, GW-0597, GW-0602, GW-0606, GW-0607, GW-0608, GW-0610, GW-0618, GW-0636, GW-0637, GW-0644, GW-0645, GW-0647, GW-0648, GW-0649, GW-0656, GW-0665, GW-0668, GW-0670, GW-0671, GW-0672, GW-0673, GW-0674, GW-0675, GW-0676, GW-0678, GW-0679, GW-0681, GW-0682, GW-0685, GW-0686, GW-0687, GW-0690, GW-0691, GW-0692, GW-0693, GW-0694, GW-0705, GW-0714, GW-0715, GW-0717, GW-0726

## Imported catalog IDs

GW-0001, GW-0002, GW-0003, GW-0004, GW-0005, GW-0007, GW-0008, GW-0010, GW-0011, GW-0012, GW-0013, GW-0014, GW-0015, GW-0016, GW-0017, GW-0018, GW-0019, GW-0020, GW-0021, GW-0023, GW-0026, GW-0027, GW-0028, GW-0029, GW-0030, GW-0031, GW-0033, GW-0035, GW-0036, GW-0038, GW-0039, GW-0041, GW-0043, GW-0044, GW-0048, GW-0049, GW-0052, GW-0053, GW-0054, GW-0055, GW-0056, GW-0057, GW-0058, GW-0059, GW-0061, GW-0063, GW-0065, GW-0068, GW-0070, GW-0072, GW-0073, GW-0074, GW-0075, GW-0076, GW-0077, GW-0078, GW-0079, GW-0080, GW-0081, GW-0082, GW-0083, GW-0084, GW-0085, GW-0086, GW-0087, GW-0088, GW-0089, GW-0090, GW-0091, GW-0092, GW-0093, GW-0094, GW-0095, GW-0096, GW-0097, GW-0098, GW-0099, GW-0100, GW-0101, GW-0102, GW-0103, GW-0104, GW-0105, GW-0107, GW-0108, GW-0110, GW-0111, GW-0112, GW-0113, GW-0114, GW-0115, GW-0116, GW-0117, GW-0118, GW-0119, GW-0120, GW-0121, GW-0123, GW-0124, GW-0125, GW-0126, GW-0127, GW-0128, GW-0129, GW-0130, GW-0131, GW-0132, GW-0133, GW-0135, GW-0136, GW-0137, GW-0138, GW-0139, GW-0140, GW-0141, GW-0146, GW-0147, GW-0148, GW-0150, GW-0151, GW-0152, GW-0153, GW-0155, GW-0156, GW-0159, GW-0161, GW-0163, GW-0165, GW-0168, GW-0171, GW-0172, GW-0173, GW-0174, GW-0176, GW-0177, GW-0178, GW-0179, GW-0180, GW-0181, GW-0183, GW-0185, GW-0186, GW-0187, GW-0188, GW-0190, GW-0192, GW-0195, GW-0196, GW-0199, GW-0200, GW-0201, GW-0202, GW-0203, GW-0204, GW-0205, GW-0206, GW-0207, GW-0208, GW-0209, GW-0210, GW-0211, GW-0212, GW-0213, GW-0214, GW-0215, GW-0216, GW-0217, GW-0219, GW-0222, GW-0223, GW-0224, GW-0225, GW-0226, GW-0228, GW-0229, GW-0230, GW-0231, GW-0232, GW-0235, GW-0236, GW-0237, GW-0238, GW-0239, GW-0241, GW-0242, GW-0243, GW-0244, GW-0245, GW-0246, GW-0247, GW-0249, GW-0250, GW-0251, GW-0252, GW-0254, GW-0255, GW-0256, GW-0257, GW-0258, GW-0259, GW-0260, GW-0261, GW-0262, GW-0263, GW-0264, GW-0265, GW-0266, GW-0268, GW-0269, GW-0270, GW-0271, GW-0272, GW-0280, GW-0282, GW-0283, GW-0284, GW-0285, GW-0286, GW-0287, GW-0288, GW-0290, GW-0291, GW-0292, GW-0294, GW-0295, GW-0296, GW-0297, GW-0298, GW-0299, GW-0300, GW-0301, GW-0302, GW-0303, GW-0304, GW-0305, GW-0306, GW-0307, GW-0309, GW-0310, GW-0311, GW-0312, GW-0313, GW-0314, GW-0315, GW-0316, GW-0322, GW-0324, GW-0325, GW-0326, GW-0328, GW-0329, GW-0330, GW-0333, GW-0334, GW-0335, GW-0338, GW-0339, GW-0344, GW-0345, GW-0351, GW-0352, GW-0362, GW-0363, GW-0364, GW-0365, GW-0366, GW-0367, GW-0368, GW-0371, GW-0375, GW-0376, GW-0377, GW-0378, GW-0379, GW-0380, GW-0381, GW-0384, GW-0386, GW-0387, GW-0389, GW-0390, GW-0392, GW-0393, GW-0394, GW-0397, GW-0398, GW-0400, GW-0401, GW-0402, GW-0403, GW-0404, GW-0407, GW-0408, GW-0416, GW-0425, GW-0433, GW-0434, GW-0438, GW-0449, GW-0456, GW-0460, GW-0462, GW-0464, GW-0465, GW-0466, GW-0468, GW-0471, GW-0475, GW-0477, GW-0478, GW-0479, GW-0484, GW-0485, GW-0486, GW-0487, GW-0488, GW-0490, GW-0494, GW-0498, GW-0499, GW-0500, GW-0502, GW-0505, GW-0509, GW-0519, GW-0530, GW-0531, GW-0537, GW-0538, GW-0539, GW-0540, GW-0542, GW-0549, GW-0558, GW-0559, GW-0566, GW-0568, GW-0571, GW-0579, GW-0584, GW-0591, GW-0594, GW-0614, GW-0621, GW-0622, GW-0625, GW-0626, GW-0627, GW-0629, GW-0642, GW-0650, GW-0653, GW-0654, GW-0658, GW-0659, GW-0661, GW-0663, GW-0666, GW-0680, GW-0683, GW-0684, GW-0688, GW-0699, GW-0704, GW-0708, GW-0723, GW-0729, GW-0733, GW-0735, GW-0042, GW-0062, GW-0064, GW-0189, GW-0191, GW-0194, GW-0253, GW-0267, GW-0331, GW-0332, GW-0385, GW-0022, GW-0024, GW-0032, GW-0040, GW-0067, GW-0134, GW-0167, GW-0169, GW-0182, GW-0184, GW-0193, GW-0197, GW-0198, GW-0220, GW-0221, GW-0233, GW-0276, GW-0278, GW-0343, GW-0361, GW-0388, GW-0399, GW-0411, GW-0412, GW-0413, GW-0422, GW-0423, GW-0424, GW-0426, GW-0428, GW-0430, GW-0431, GW-0432, GW-0437, GW-0439, GW-0441, GW-0442, GW-0443, GW-0444, GW-0445, GW-0446, GW-0447, GW-0448, GW-0450, GW-0451, GW-0452, GW-0455, GW-0459, GW-0463, GW-0467, GW-0473, GW-0474, GW-0483, GW-0489, GW-0491, GW-0495, GW-0496, GW-0503, GW-0506, GW-0508, GW-0510, GW-0511, GW-0513, GW-0514, GW-0515, GW-0516, GW-0517, GW-0518, GW-0520, GW-0522, GW-0523, GW-0524, GW-0525, GW-0527, GW-0528, GW-0529, GW-0535, GW-0536, GW-0541, GW-0544, GW-0545, GW-0547, GW-0548, GW-0550, GW-0551, GW-0552, GW-0553, GW-0554, GW-0555, GW-0560, GW-0561, GW-0562, GW-0563, GW-0564, GW-0567, GW-0572, GW-0573, GW-0574, GW-0582, GW-0583, GW-0585, GW-0586, GW-0587, GW-0588, GW-0593, GW-0595, GW-0596, GW-0598, GW-0599, GW-0600, GW-0601, GW-0603, GW-0604, GW-0605, GW-0609, GW-0611, GW-0612, GW-0613, GW-0615, GW-0616, GW-0617, GW-0619, GW-0620, GW-0623, GW-0624, GW-0630, GW-0631, GW-0632, GW-0633, GW-0634, GW-0635, GW-0638, GW-0639, GW-0640, GW-0641, GW-0643, GW-0646, GW-0651, GW-0652, GW-0655, GW-0657, GW-0660, GW-0662, GW-0664, GW-0667, GW-0669, GW-0677, GW-0689, GW-0695, GW-0696, GW-0697, GW-0698, GW-0700, GW-0701, GW-0702, GW-0703, GW-0706, GW-0707, GW-0709, GW-0710, GW-0711, GW-0712, GW-0713, GW-0716, GW-0718, GW-0719, GW-0720, GW-0721, GW-0722, GW-0724, GW-0725, GW-0727, GW-0728, GW-0730, GW-0731, GW-0732, GW-0734, GW-0009, GW-0025, GW-0037, GW-0045, GW-0046

## Original workbook status totals (before follow-up)

- Approved: 695
- Changed: 38
- Needs review: 148
- Question: 5
