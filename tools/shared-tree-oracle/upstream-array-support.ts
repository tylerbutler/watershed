/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { FluidClientVersion, type CodecWriteOptions } from "../codec/index.js";
import { RevisionTagCodec } from "../core/index.js";
import { FormatValidatorBasic } from "../external-utilities/index.js";
import {
	fieldBatchCodecBuilder,
	fieldKindConfigurations,
	fieldKinds,
	makeModularChangeCodecFamily,
	ModularChangeFamily,
	TreeCompressionStrategy,
} from "../feature-libraries/index.js";
import { testIdCompressor } from "./utils.js";

export function makeArrayModularFamily(): {
	readonly family: ModularChangeFamily;
	readonly codecOptions: CodecWriteOptions;
} {
	const codecOptions: CodecWriteOptions = {
		jsonValidator: FormatValidatorBasic,
		minVersionForCollab: FluidClientVersion.v2_117,
	};
	const revisionTagCodec = new RevisionTagCodec(testIdCompressor);
	const fieldBatchCodec = fieldBatchCodecBuilder.build(codecOptions);
	const codecs = makeModularChangeCodecFamily(
		fieldKindConfigurations,
		revisionTagCodec,
		fieldBatchCodec,
		codecOptions,
		TreeCompressionStrategy.Compressed,
	);
	return {
		family: new ModularChangeFamily(fieldKinds, codecs, codecOptions),
		codecOptions,
	};
}
