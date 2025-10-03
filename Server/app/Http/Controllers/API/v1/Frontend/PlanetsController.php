<?php

namespace App\Http\Controllers\API\V1\Frontend;

use Illuminate\Support\Str;
use App\Http\Controllers\API\V1\Frontend\FrontendBaseController;
use Illuminate\Http\Request;

/**
 * PlanetsController
 *
 * Exposes quiz content for a given Post (by id) tailored for the Flutter client.
 * - All inline comments and strings are in English as requested.
 * - No business logic has been changed; only documentation/comments/messages.
 */
class PlanetsController extends FrontendBaseController
{
    public function __construct()
    {
        parent::__construct();
        // Base metadata used by shared frontend scaffolding
        $this->var['model_type']          = 'post';
        $this->var['model_name']          = 'posts';
        $this->var['model_api']           = 'planets';
        $this->var['model_name_singular'] = Str::singular($this->var['model_name']);
        $this->var['model_class']         = 'App\Models\Post';
        $this->var['model_icon']          = '<i class="iconix icon-book"></i>';
        $this->var['model_view']          = $this->var['model_framework'] . '.frontend.' . $this->var['model_name'];
        $this->var['breadcrumbs'][route('frontend.home')] = __('panel.page_user');
        // $this->var['breadcrumbs'][route('frontend.posts.index')] = __('panel.posts');

        // Whitelists for index/show payloads (if used by the base controller)
        $this->var['model_index_fields'] = ['id', 'name', 'description', 'thumbnail'];
        $this->var['model_show_fields']  = ['id', 'name', 'description', 'thumbnail', 'body', 'attributes'];
        $this->var['model_quiz_fields']  = ['id', 'name', 'quizzes'];
    }

    /**
     * Validation rules selector for various controller operations.
     * Currently returns empty rule sets; extend as needed.
     */
    public function getRules($params)
    {
        $type                 = $params['type'] ?? 'index';
        $input                = $params['input'] ?? [];
        $model_name           = $params['model_name'] ?? null;
        $model_name_singular  = $params['model_name_singular'] ?? null;
        $$model_name_singular = $params['$model_name_singular'] ?? null;

        $input['language'] = $input['language'] ?? null;

        if ($type == 'index') {
            return [];
        } elseif ($type == 'trash') {
            return [];
        } elseif ($type == 'update') {
            return [];
        } elseif ($type == 'store') {
            return [];
        } elseif ($type == 'show') {
            return [
                'ref'  => 'nullable|in:telegram,instagram,twitter,google',
                'code' => 'nullable|numeric'
            ];
        } else {
            return [];
        }
        return [];
    }

    /**
     * GET /api/v1/frontend/planets/{id}/questions
     *
     * Returns a normalized quiz payload for the given Post id.
     * - Renames "name" to "title"
     * - Normalizes "quizzes" array:
     *     * drops the "order" field
     *     * ensures "correctIndex" is an integer
     */
    public function questions(Request $request, $id)
    {
        // Spread $this->var into local variables expected by base scaffolding
        foreach ($this->var as $key => $value) {
            $$key = $value;
        }

        // Find the item by numeric id (or change to slug if desired)
        $item = $model_class::where('id', $id)->select($model_quiz_fields)->first();

        if (!$item) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => 'Item not found.',
                'data'    => null,
            ], 404, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
        }

        $data = [];
        foreach ($model_quiz_fields as $field) {
            if ($field === 'name') {
                // Map 'name' to 'title' for client convenience
                $data['title'] = $item->$field;
            } elseif ($field === 'quizzes') {

                // Normalize quizzes collection
                $quizzes = [];

                foreach ($item->$field as $question) {
                    // Remove "order" if present (not needed on client)
                    unset($question['order']);

                    // Ensure correctIndex is an integer (source may be string)
                    $question['correctIndex'] = (int) $question['correctIndex'];

                    // Keep only the essential fields
                    $quizzes[] = [
                        'question'     => $question['question'],
                        'options'      => $question['options'],
                        'correctIndex' => $question['correctIndex'],
                    ];
                }

                $data['questions'] = $quizzes;
            } else {
                // Pass through other allowed fields unmodified
                $data[$field] = $item->$field;
            }
        }

        // Example static payload (kept as commented reference)
        // $data['questions'] = [
        //     [
        //         "question" => "Which planet is known as the Red Planet?",
        //         "questionImage" => null,
        //         "options" => ["Venus", "Mars", "Jupiter", "Saturn"],
        //         "correctIndex" => 1
        //     ],
        //     ...
        // ];

        return response()->json([
            'succeed' => true,
            'status'  => 200,
            'message' => 'Operation successful.',
            'data'    => $data,
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }
}
