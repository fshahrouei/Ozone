<?php

namespace App\Http\Controllers\API\V1\Frontend;

use Illuminate\Support\Str;
use App\Http\Controllers\API\V1\Frontend\FrontendBaseController;
use Illuminate\Http\Request;

/**
 * PostsController
 *
 * Lightweight frontend controller metadata + rule selector used by shared
 * scaffolding. No business logic is modified; comments and docs are in English.
 */
class PostsController extends FrontendBaseController
{
    public function __construct()
    {
        parent::__construct();
        // Base metadata consumed by the generic frontend layer
        $this->var['model_type']          = 'post';
        $this->var['model_name']          = 'posts';
        $this->var['model_api']           = 'posts';
        $this->var['model_name_singular'] = Str::singular($this->var['model_name']);
        $this->var['model_class']         = 'App\Models\Post';
        $this->var['model_icon']          = '<i class="iconix icon-book"></i>';
        $this->var['model_view']          = $this->var['model_framework'] . '.frontend.' . $this->var['model_name'];
        $this->var['breadcrumbs'][route('frontend.home')] = __('panel.page_user');
        // $this->var['breadcrumbs'][route('frontend.posts.index')] = __('panel.posts');

        // Whitelists for index/show payloads (used by the base controller layer)
        $this->var['model_index_fields'] = ['id', 'name', 'description', 'thumbnail'];
        $this->var['model_show_fields']  = ['id', 'name', 'description', 'thumbnail', 'body'];
    }

    /**
     * Rule selector for different actions. Currently returns empty or minimal
     * sets; extend per your validation needs without changing call sites.
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
                'code' => 'nullable|numeric',
            ];
        } else {
            return [];
        }
        return [];
    }
}
