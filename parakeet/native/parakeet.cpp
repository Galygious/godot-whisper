#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <sherpa-onnx/c-api/c-api.h>
#include <chrono>
#include <mutex>

using namespace godot;

class ParakeetRecognizer : public RefCounted {
    GDCLASS(ParakeetRecognizer, RefCounted);
    const SherpaOnnxOfflineRecognizer *recognizer = nullptr;
    std::mutex mutex;
    String last_error;

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("load_model", "directory", "num_threads"), &ParakeetRecognizer::load_model, DEFVAL(2));
        ClassDB::bind_method(D_METHOD("transcribe", "samples", "sample_rate"), &ParakeetRecognizer::transcribe, DEFVAL(16000));
        ClassDB::bind_method(D_METHOD("get_last_error"), &ParakeetRecognizer::get_last_error);
    }

public:
    String get_last_error() const { return last_error; }

    bool load_model(const String &directory, int num_threads) {
        std::lock_guard<std::mutex> lock(mutex);
        last_error = "";
        if (recognizer) {
            SherpaOnnxDestroyOfflineRecognizer(recognizer);
            recognizer = nullptr;
        }
        const String files[] = {"encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"};
        for (const String &file : files) {
            if (!FileAccess::file_exists(directory.path_join(file))) {
                last_error = "Missing Parakeet model file: " + directory.path_join(file);
                return false;
            }
        }
        // ONNX Runtime needs real filesystem paths, not resources inside a PCK.
        const String base = ProjectSettings::get_singleton()->globalize_path(directory);
        const CharString encoder = base.path_join(files[0]).utf8();
        const CharString decoder = base.path_join(files[1]).utf8();
        const CharString joiner = base.path_join(files[2]).utf8();
        const CharString tokens = base.path_join(files[3]).utf8();
        SherpaOnnxOfflineRecognizerConfig config = {};
        config.feat_config.sample_rate = 16000;
        config.feat_config.feature_dim = 80;
        config.model_config.transducer.encoder = encoder.get_data();
        config.model_config.transducer.decoder = decoder.get_data();
        config.model_config.transducer.joiner = joiner.get_data();
        config.model_config.tokens = tokens.get_data();
        config.model_config.model_type = "nemo_transducer";
        config.model_config.provider = "cpu";
        config.model_config.num_threads = num_threads < 1 ? 1 : (num_threads > 8 ? 8 : num_threads);
        config.decoding_method = "greedy_search";
        config.max_active_paths = 4;
        recognizer = SherpaOnnxCreateOfflineRecognizer(&config);
        if (!recognizer) {
            last_error = "Parakeet initialization failed. Use the v2 INT8 encoder, decoder, joiner and tokens together.";
        }
        return recognizer != nullptr;
    }

    Dictionary transcribe(const PackedFloat32Array &samples, int sample_rate) {
        std::lock_guard<std::mutex> lock(mutex);
        Dictionary output;
        output["text"] = "";
        output["error"] = "";
        output["seconds"] = 0.0;
        if (!recognizer || samples.is_empty() || sample_rate < 8000 || sample_rate > 192000) {
            output["error"] = !recognizer ? "Load the Parakeet model before transcribing." : "Provide nonempty mono float samples and a valid sample rate.";
            return output;
        }
        const auto start = std::chrono::steady_clock::now();
        const auto *stream = SherpaOnnxCreateOfflineStream(recognizer);
        if (!stream) {
            output["error"] = "Failed to create Parakeet decoding stream.";
            return output;
        }
        SherpaOnnxAcceptWaveformOffline(stream, sample_rate, samples.ptr(), samples.size());
        SherpaOnnxDecodeOfflineStream(recognizer, stream);
        const auto *result = SherpaOnnxGetOfflineStreamResult(stream);
        if (result) {
            output["text"] = String::utf8(result->text);
            SherpaOnnxDestroyOfflineRecognizerResult(result);
        } else {
            output["error"] = "Parakeet did not return a result.";
        }
        SherpaOnnxDestroyOfflineStream(stream);
        output["seconds"] = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        return output;
    }

    ~ParakeetRecognizer() {
        if (recognizer) {
            SherpaOnnxDestroyOfflineRecognizer(recognizer);
        }
    }
};

void initialize_parakeet(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(ParakeetRecognizer);
    }
}
void uninitialize_parakeet(ModuleInitializationLevel level) {}

extern "C" GDExtensionBool GDE_EXPORT godot_parakeet_library_init(
        GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr library,
        GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject object(address, library, initialization);
    object.register_initializer(initialize_parakeet);
    object.register_terminator(uninitialize_parakeet);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return object.init();
}
